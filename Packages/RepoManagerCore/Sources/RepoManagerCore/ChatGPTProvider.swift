import Foundation

public enum ProviderFailure {
    public static func safe(_ error: Error) -> Error {
        if error is CancellationError { return RMError.cancelled }
        return (error as? ChatGPTServiceError).map { $0 as Error }
            ?? (error as? ChatGPTSignInError).map { $0 as Error }
            ?? (error as? RMError ?? .connection)
    }
}

/// Official public Responses API with OAuth credentials for the selected
/// registration. It never retries inference or changes the user's billing path.
public struct ChatGPTProviderClient: ProviderClient {
    private let connections: ChatGPTConnectionStore
    private let transport: any HTTPTransport
    public init(connections: ChatGPTConnectionStore, transport: any HTTPTransport = SecureHTTPTransport()) {
        self.connections = connections; self.transport = transport
    }
    public func catalog(_ profile: ProviderProfile) async throws -> [ModelMetadata] {
        try ChatGPTAuth.validateProfile(profile); try ProviderDisclosure.validate(profile: profile, model: "catalog")
        let token = try await connections.accessToken(for: profile)
        var request = URLRequest(url: URL(string: ChatGPTAuth.resource + "/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await transport.send(request, limit: 4 * 1024 * 1024)
        guard result.status == 200 else { throw ChatGPTServiceError(status: result.status, body: result.json, requestID: ChatGPTConnectionStore.requestID(result.headers)) }
        guard let rows = result.json["models"].array, rows.count <= 2000 else { throw RMError.upstream }
        var seen = Set<String>(), models: [ModelMetadata] = []
        for row in rows where row["visibility"].string == "list" {
            guard let slug = row["slug"].string, let name = row["display_name"].string, !name.isEmpty, name.utf8.count <= 256 else { throw RMError.upstream }
            _ = try InputValidation.model(slug)
            guard seen.insert(slug).inserted else { continue }
            var model = ModelMetadata(id: slug); model.displayName = name; model.format = .responses
            models.append(model)
        }
        return models // Preserve the account-specific server ordering.
    }
    public func stream(_ input: RunRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(64)) { output in
            let task = Task {
                do {
                    try ChatGPTAuth.validateProfile(input.profile)
                    guard input.profile.models.contains(where: { $0.id == input.model }) else { throw RMError.unavailable }
                    try ProviderDisclosure.validate(profile: input.profile, model: input.model)
                    let token = try await connections.accessToken(for: input.profile)
                    let request = try ProviderWire.request(input, key: token)
                    var status: Int?, requestID: String?, failureBody = Data()
                    var parser = SSEParser(), decoder = ProviderEventDecoder(format: .responses), completed = false
                    func events(_ frame: SSEFrame) throws -> [ChatEvent] {
                        if frame.data == Data("[DONE]".utf8) { return [] }
                        let root = try JSON.parse(frame.data), type = root["type"].string ?? frame.event
                        if type == "response.failed" || type == "error" || root["error"] != .null {
                            throw ChatGPTServiceError(status: status ?? 200, body: type == "response.failed" ? root["response"] : root, requestID: requestID)
                        }
                        if type == "response.incomplete" { throw RMError.upstream }
                        for item in [root["item"]] + (root["response"]["output"].array ?? []) {
                            if item["type"].string == "function_call", let namespace = item["namespace"].string,
                               namespace != "repo_manager" { throw RMError.upstream }
                        }
                        if type == "response.completed" { completed = true }
                        return try decoder.decode(frame)
                    }
                    responseStream: for try await event in transport.streamResponse(request, limit: 8 * 1024 * 1024) {
                        try Task.checkCancellation()
                        switch event {
                        case .response(let code, let headers):
                            guard status == nil else { throw RMError.upstream }; status = code
                            requestID = ChatGPTConnectionStore.requestID(headers)
                        case .data(let bytes):
                            guard let status else { throw RMError.upstream }
                            if status != 200 {
                                guard failureBody.count + bytes.count <= 256 * 1024 else { throw RMError.tooLarge }
                                failureBody.append(bytes)
                            } else {
                                var packet: [ChatEvent] = []
                                for frame in try parser.feed(bytes) {
                                    packet += try events(frame)
                                    if completed { break }
                                }
                                for value in StreamDelivery.coalesced(packet) { try await StreamDelivery.send(value, to: output) }
                                // response.completed is the protocol boundary. Do
                                // not turn a later socket close/reset into a failed
                                // answer, or leave a completed turn waiting on EOF.
                                if completed { break responseStream }
                            }
                        }
                    }
                    guard let status else { throw RMError.connection }
                    if status != 200 { throw ChatGPTServiceError(status: status, body: (try? JSON.parse(failureBody)) ?? .null, requestID: requestID) }
                    if !completed {
                        var packet: [ChatEvent] = []
                        for frame in try parser.feed(Data(), final: true) { packet += try events(frame); if completed { break } }
                        for value in StreamDelivery.coalesced(packet) { try await StreamDelivery.send(value, to: output) }
                    }
                    guard completed else { throw RMError.connection }
                    output.finish()
                } catch { output.finish(throwing: ProviderFailure.safe(error)) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
}
