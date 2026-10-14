import Foundation
import Network

/// The sole cleartext exception: a short-lived OAuth callback bound to IPv4
/// loopback. It never accepts content, tokens, tool requests or LAN connections.
public struct ChatGPTLoopbackRequestParser: Sendable {
    private var bytes = Data()
    public init() {}
    public mutating func feed(_ data: Data, redirectURI: URL) throws -> URL? {
        try ChatGPTAuth.validateRedirect(redirectURI)
        bytes.append(data); guard bytes.count <= 16384 else { throw RMError.tooLarge }
        guard let end = bytes.range(of: Data([13, 10, 13, 10])) else { return nil }
        guard end.upperBound == bytes.count, let text = String(data: bytes.prefix(end.lowerBound), encoding: .utf8) else { throw ChatGPTSignInError.invalidCallback }
        let lines = text.components(separatedBy: "\r\n"), request = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[0] == "GET", request[2] == "HTTP/1.1", request[1].hasPrefix("/auth/callback?"),
              request[1].utf8.count <= 8192, !request[1].contains("#"),
              !request[1].unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }) else { throw ChatGPTSignInError.invalidCallback }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { throw ChatGPTSignInError.invalidCallback }
            let name = String(line[..<colon]).lowercased(), value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard headers[name] == nil, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw ChatGPTSignInError.invalidCallback }
            headers[name] = value
        }
        guard headers["host"] == "127.0.0.1:\(redirectURI.port!)", headers["transfer-encoding"] == nil,
              headers["content-length"] == nil || headers["content-length"] == "0",
              let url = URL(string: "http://127.0.0.1:\(redirectURI.port!)" + request[1]) else { throw ChatGPTSignInError.invalidCallback }
        return url
    }
}

public actor ChatGPTLoopbackListener {
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var attempt: ChatGPTAuthorizationAttempt?
    private var redirectURI: URL?
    private var browserReturnURL: URL?
    private var handled = false
    private let queue = DispatchQueue(label: "com.mesutcydev.repomanager.chatgpt-callback")
    private let callbacks: AsyncThrowingStream<URL, Error>
    private let output: AsyncThrowingStream<URL, Error>.Continuation
    private var timeout: Task<Void, Never>?
    public init() {
        let pair = AsyncThrowingStream<URL, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        callbacks = pair.stream; output = pair.continuation
    }
    public func start() async throws -> URL {
        guard listener == nil, !handled else { throw RMError.invalidInput }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
        parameters.allowLocalEndpointReuse = false
        let listener = try NWListener(using: parameters, on: .any)
        let ready = AsyncThrowingStream<UInt16, Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        listener.stateUpdateHandler = { [weak listener] state in
            switch state {
            case .ready:
                if let port = listener?.port { ready.continuation.yield(port.rawValue); ready.continuation.finish() }
                else { ready.continuation.finish(throwing: RMError.connection) }
            case .failed: ready.continuation.finish(throwing: RMError.connection)
            case .waiting: ready.continuation.finish(throwing: RMError.connection)
            case .cancelled: ready.continuation.finish(throwing: RMError.cancelled)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in Task { await self?.accept(connection) } }
        self.listener = listener; listener.start(queue: queue)
        return try await withTaskCancellationHandler {
            for try await port in ready.stream {
                try Task.checkCancellation()
                guard let url = URL(string: "http://127.0.0.1:\(port)/auth/callback") else { throw RMError.invalidInput }
                redirectURI = url; return url
            }
            throw RMError.connection
        } onCancel: { Task { await self.stop() } }
    }
    public func expect(_ attempt: ChatGPTAuthorizationAttempt, browserReturnURL: URL) throws {
        guard attempt.redirectURI == redirectURI, !handled,
              browserReturnURL.scheme == "com.mesutcydev.repomanager.chatgpt", browserReturnURL.host == "complete",
              browserReturnURL.query == nil, browserReturnURL.fragment == nil else { throw RMError.invalidInput }
        self.attempt = attempt; self.browserReturnURL = browserReturnURL
        timeout = Task { do { try await Task.sleep(for: .seconds(600)); self.stop(failure: ChatGPTSignInError.expired) } catch {} }
    }
    public func waitForCallback() async throws -> URL {
        try await withTaskCancellationHandler {
            for try await url in callbacks { try Task.checkCancellation(); return url }
            throw RMError.cancelled
        } onCancel: { Task { await self.stop() } }
    }
    public func stop(failure: Error = RMError.cancelled) {
        handled = true; timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }; connections.removeAll()
        attempt = nil; browserReturnURL = nil; output.finish(throwing: failure)
    }
    private func accept(_ connection: NWConnection) {
        guard !handled, attempt != nil, connections.count < 8,
              case .hostPort(let host, _) = connection.endpoint, case .ipv4(let address) = host,
              address == IPv4Address("127.0.0.1") else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection; connection.start(queue: queue)
        Task { await handle(connection, id: id) }
    }
    private func handle(_ connection: NWConnection, id: UUID) async {
        let deadline = Task { do { try await Task.sleep(for: .seconds(5)); connection.cancel() } catch {} }
        defer { deadline.cancel(); connection.cancel(); connections[id] = nil }
        do {
            guard let attempt, let returnURL = browserReturnURL else { throw RMError.cancelled }
            var parser = ChatGPTLoopbackRequestParser(), callbackURL: URL?
            while callbackURL == nil {
                let (data, eof) = try await receive(connection)
                callbackURL = try parser.feed(data, redirectURI: attempt.redirectURI)
                if eof && callbackURL == nil { throw ChatGPTSignInError.invalidCallback }
            }
            guard let callbackURL, !handled else { throw RMError.cancelled }
            var declined = false
            do { _ = try attempt.callback(callbackURL) }
            catch ChatGPTSignInError.declined { declined = true }
            // Invalid state/path/registration requests receive 400 and do not
            // consume the waiting sign-in or close its listener.
            handled = true; timeout?.cancel(); listener?.cancel(); listener = nil
            let reply = "HTTP/1.1 302 Found\r\nLocation: \(returnURL.absoluteString)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            // Safari can reset the response socket when switching apps. Keep
            // the validated OAuth result for foreground completion regardless.
            try? await send(Data(reply.utf8), connection: connection)
            if declined { output.finish(throwing: ChatGPTSignInError.declined) }
            else { output.yield(callbackURL); output.finish() }
            self.attempt = nil; browserReturnURL = nil
        } catch {
            if handled { output.finish(throwing: ProviderFailure.safe(error)) }
            else { try? await send(Data("HTTP/1.1 400 Bad Request\r\nCache-Control: no-store\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), connection: connection) }
        }
    }
    private func receive(_ connection: NWConnection) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, eof, error in
                if error != nil { continuation.resume(throwing: RMError.connection) }
                else { continuation.resume(returning: (data ?? Data(), eof)) }
            }
        }
    }
    private func send(_ data: Data, connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: RMError.connection) }
                else { continuation.resume() }
            })
        }
    }
}
