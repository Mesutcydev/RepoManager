import Foundation
import RepoManagerCore

enum DevelopmentFixtures {
    static var sessionDesign: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--session-design-fixtures")
        #else
        false
        #endif
    }
    static var storeScreenshots: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--store-screenshot-fixtures")
        #else
        false
        #endif
    }
    static var fileEditorScreenshot: Bool {
        storeScreenshots && ProcessInfo.processInfo.arguments.contains("--file-editor-screenshot-fixtures")
    }
    static var pro: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--pro-fixtures")
        #else
        false
        #endif
    }
    static var proOwned: Bool {
        #if DEBUG
        pro && ProcessInfo.processInfo.arguments.contains("--pro-owned-fixtures")
        #else
        false
        #endif
    }
    static var chatGPTPairing: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--chatgpt-pairing-fixtures")
        #else
        false
        #endif
    }
    static var githubPairing:Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--github-pairing-fixtures")
        #else
        false
        #endif
    }
    static var lightAppearance:Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--light-appearance-fixtures")
        #else
        false
        #endif
    }
    static var oledAppearance: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--oled-appearance-fixtures")
        #else
        false
        #endif
    }
    static var largeText:Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--large-text-fixtures")
        #else
        false
        #endif
    }
    static var rtl:Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--rtl-fixtures")
        #else
        false
        #endif
    }
    static var repositoryWorkspace:Bool {
        #if DEBUG
        enabled && (ProcessInfo.processInfo.arguments.contains("--repository-fixtures") || githubPairing || contextBudget || extendedAudit || replyStability || branchFailure || completedResponses || backgroundResume)
        #else
        false
        #endif
    }
    static var contextBudget: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--context-budget-fixtures")
        #else
        false
        #endif
    }
    static var extendedAudit: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--extended-audit-fixtures")
        #else
        false
        #endif
    }
    static var backgroundResume: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--background-resume-fixtures")
        #else
        false
        #endif
    }
    static var replyStability: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--reply-stability-fixtures")
        #else
        false
        #endif
    }
    static var rapidStreaming: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--rapid-stream-fixtures")
        #else
        false
        #endif
    }
    static var completedResponses: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--completed-response-fixtures")
        #else
        false
        #endif
    }
    static var emptyResponse: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--empty-response-fixtures")
        #else
        false
        #endif
    }
    static var branchFailure: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--branch-request-error-fixtures")
        #else
        false
        #endif
    }
    static var syncFailure: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--background-sync-error-fixtures")
        #else
        false
        #endif
    }
    static var reducedMotion: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--reduced-motion-fixtures")
        #else
        false
        #endif
    }
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-fixtures")
        #else
        false
        #endif
    }
    /// `--workspace <name>` opens a workspace directly, for screen-by-screen visual checks.
    static var workspace: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard enabled, let index = arguments.firstIndex(of:"--workspace"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
        #else
        nil
        #endif
    }
    static var onboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--onboarding-fixtures")
        #else
        false
        #endif
    }
}

#if DEBUG
/// Synthetic GitHub data for native screen verification. Never available in Release; makes no network requests.
struct DevelopmentGitHubTransport:HTTPTransport {
    private let sha = String(repeating:"a",count:40)
    func send(_ request:URLRequest,limit:Int) async throws -> HTTPResult {
        try Task.checkCancellation()
        let path = request.url?.path ?? ""
        if DevelopmentFixtures.branchFailure, path.hasSuffix("/branches") {
            try await Task.sleep(for: .milliseconds(300)); throw RMError.connection
        }
        if DevelopmentFixtures.replyStability, path.contains("/git/blobs/") {
            try await Task.sleep(for: .seconds(5))
        }
        if DevelopmentFixtures.backgroundResume, path.hasSuffix("/git/blobs/"+String(repeating:"b",count:40)) {
            try await Task.sleep(for: .seconds(30))
        }
        let json:JSON
        if DevelopmentFixtures.githubPairing,request.url?.host == "github.com",request.httpMethod == "POST" {
            if path == "/login/device/code" {
                json = .object(["device_code":"synthetic-device-code","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":600,"interval":1])
            } else if path == "/login/oauth/access_token" {
                json = .object(["error":"authorization_pending"])
            } else { throw RMError.forbidden }
        } else {
            guard request.httpMethod == nil || request.httpMethod == "GET" else { throw RMError.forbidden }
            if path == "/user" { json = .object(["id":7,"login":"preview-maintainer"]) }
        else if path == "/user/repos" { json = .array([.object(["id":42,"name":"repo-manager","full_name":"preview-maintainer/repo-manager","default_branch":"main","owner":.object(["login":"preview-maintainer"]),"description":"Synthetic repository for branch recovery."])]) }
        else if path == "/repositories/42" || path == "/repos/preview-maintainer/repo-manager" { json = .object(["id":42,"full_name":"preview-maintainer/repo-manager","permissions":.object(["pull":true,"push":true,"admin":false])]) }
        else if path.contains("/git/ref/") { json = .object(["object":.object(["sha":.string(sha)])]) }
        else if path.contains("/git/commits/") { json = .object(["sha":.string(sha),"tree":.object(["sha":.string(sha)]),"parents":.array([])]) }
        else if path.contains("/git/trees/") {
            var entries: [JSON] = DevelopmentFixtures.contextBudget || DevelopmentFixtures.backgroundResume ? (0..<500).map { index in
                .object(["path": .string("Sources/Feature\(index)/RepositoryAuditAndPresentationSettings.swift"), "type": "blob", "mode": "100644", "sha": .string(sha), "size": 128])
            } : [.object(["path":"README.md","type":"blob","mode":"100644","sha":.string(sha),"size":128])]
            if DevelopmentFixtures.backgroundResume {
                entries += [.object(["path":"README.md","type":"blob","mode":"100644","sha":.string(sha),"size":128]),
                            .object(["path":"Pending.swift","type":"blob","mode":"100644","sha":.string(String(repeating:"b",count:40)),"size":128])]
            }
            json = .object(["truncated":false,"tree":.array(entries)])
        }
        else if path.contains("/git/blobs/") { json = .object(["encoding":"base64","content":.string(Data("# Repo Manager\n\nA thoughtful workspace for repositories.\n\nEvery remote change starts with your review.\n".utf8).base64EncodedString())]) }
        else if path.hasSuffix("/pulls/1/files") { json = .array([.object(["filename":"README.md","status":"modified","additions":1,"deletions":1,"patch":"@@ -1 +1 @@\n-# Repository\n+# Repo Manager"])]) }
        else if path.hasSuffix("/pulls") { json = .array([.object(["id":101,"number":1,"title":"Give the repository a clearer introduction","state":"open","body":"This proposal improves the README and keeps the change easy to review." ])]) }
        else if path.hasSuffix("/issues") { json = .array([.object(["id":102,"number":2,"title":"Improve the contributor guide","state":"open","body":"Explain the review workflow and setup steps." ])]) }
            else { json = .array([]) }
        }
        guard json.encoded.count <= limit else { throw RMError.tooLarge }; return HTTPResult(status:200,data:json.encoded)
    }
    func stream(_ request:URLRequest,limit:Int) -> AsyncThrowingStream<Data,Error> { AsyncThrowingStream { $0.finish(throwing:RMError.unsupported) } }
}
/// Uses the production run and tool coordinators; no HTTP or credentials are involved.
struct DevelopmentProvider: ProviderClient {
    func stream(_ request:RunRequest) -> AsyncThrowingStream<ChatEvent,Error> {
        if DevelopmentFixtures.rapidStreaming || DevelopmentFixtures.completedResponses || DevelopmentFixtures.emptyResponse { return DevelopmentResponseStream.stream(request) }
        return AsyncThrowingStream { output in
            let task = Task {
                do {
                    if DevelopmentFixtures.backgroundResume {
                        try Self.backgroundAudit(request,output:output); output.finish(); return
                    }
                    if DevelopmentFixtures.extendedAudit {
                        let last = request.messages.last(where: { $0.role == .tool })?.toolCallID?.split(separator: "_").last.flatMap { Int($0) } ?? -1
                        let round = last + 1
                        if round >= 35 || request.tools.isEmpty {
                            output.yield(.text("# Extended repository audit complete\n\nCompleted 35 read-only tool calls through the production coordinator. This synthetic run verifies that a repository audit continues beyond the previous 25-call limit and returns findings. No files were changed."))
                            output.yield(.finish("stop"))
                        } else {
                            output.yield(.text("Inspecting repository evidence (\(round+1)/35)."))
                            output.yield(.tool(ToolCall(id: "extended_read_\(round)", name: "read_file", arguments: .object(["path": "README.md"]))))
                            output.yield(.finish("tool_calls"))
                        }
                        output.finish(); return
                    }
                    if DevelopmentFixtures.replyStability {
                        try await Self.replyStability(request, output: output); output.finish(); return
                    }
                    output.yield(.reasoning("Checking the selected conversation and its available tools."))
                    try await Task.sleep(for:.milliseconds(350)); try Task.checkCancellation()
                    if DevelopmentFixtures.contextBudget {
                        try await Self.repositoryAudit(request, output: output)
                        output.finish(); return
                    }
                    if !request.messages.contains(where:{ $0.role == .tool }), request.messages.last?.text.contains("calculator") == true {
                        output.yield(.tool(ToolCall(id:"fixture-calculator",name:"calculator",arguments:.object(["expression":"2+2"])))); output.yield(.finish("tool_calls")); output.finish(); return
                    }
                    let words = "This is a synthetic streaming response for native interface verification. It exercises reasoning timing, stable message identity, follow scrolling, the composer, and cancellation through the production run coordinator. Your draft and reading position stay with the conversation.".split(separator:" ")
                    for word in words { try Task.checkCancellation(); output.yield(.text(String(word)+" ")); try await Task.sleep(for:.milliseconds(140)) }
                    output.yield(.usage(Usage(input:42,output:35))); output.yield(.finish("stop")); output.finish()
                } catch { output.finish(throwing: ProviderFailure.safe(error)) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
    private static func backgroundAudit(_ request: RunRequest, output: AsyncThrowingStream<ChatEvent, Error>.Continuation) throws {
        guard request.messages.contains(where: { $0.role == .user && $0.text == "Audit repo for cleanup and better display" }) else { throw RMError.invalidInput }
        if request.messages.contains(where: { $0.role == .user && $0.continuationOf != nil }) {
            let calls = request.messages.filter { $0.role == .assistant }.flatMap(\.calls).map(\.id)
            let results = request.messages.filter { $0.role == .tool }.compactMap(\.toolCallID)
            guard calls == results, results.contains("background_map"), results.contains("background_files") else { throw RMError.invalidInput }
            if results.contains("resumed_read") {
                output.yield(.text("# Background audit resumed\n\nThe original cleanup and display request, completed file list, and interrupted map were retained after reopening. The next read completed and the audit returned findings in Plan mode. No files were changed."))
                output.yield(.finish("stop"))
            } else {
                output.yield(.tool(ToolCall(id:"resumed_read",name:"read_file",arguments:.object(["path":"README.md"]))))
                output.yield(.finish("tool_calls"))
            }
        } else {
            output.yield(.text("I’ll review repository organization, presentation, and UI for cleanup opportunities."))
            output.yield(.tool(ToolCall(id:"background_files",name:"list_files",arguments:.object([:]))))
            output.yield(.tool(ToolCall(id:"background_map",name:"repository_context_map",arguments:.object([:]))))
            output.yield(.finish("tool_calls"))
        }
    }
    /// Completed native Responses items exercise the production decoder, wire
    /// encoder, history restoration and context compaction on a 500-file audit.
    private static func repositoryAudit(_ request: RunRequest, output: AsyncThrowingStream<ChatEvent, Error>.Continuation) async throws {
        let turn = request.messages.last(where: { $0.role == .user })!.id.uuidString
        let native: [JSON] = [
            .object(["type": "reasoning", "id": .string("rs_\(turn)"), "encrypted_content": "synthetic-opaque-audit-state", "summary": .array([])]),
            .object(["type": "message", "id": .string("msg_\(turn)"), "role": "assistant", "phase": "commentary", "status": "completed",
                     "content": .array([.object(["type": "output_text", "text": "Inspecting the repository.\n\n", "annotations": .array([])])])]),
            .object(["type": "function_call", "id": .string("fc_z_\(turn)"), "call_id": .string("map_\(turn)"), "name": "repository_context_map", "namespace": "repo_manager", "arguments": "  {}  ", "status": "completed"]),
            .object(["type": "function_call", "id": .string("fc_a_\(turn)"), "call_id": .string("files_\(turn)"), "name": "list_files", "namespace": "repo_manager", "arguments": "{}", "status": "completed"])
        ]
        if request.messages.last?.role == .tool {
            // The UI fixture uses its isolated Apple profile. Keep its identity
            // binding while checking the same Responses encoding as ChatGPT.
            var wire = request; wire.profile.preset = .openAI; wire.profile.format = .responses; wire.profile.models = []
            let input = try ProviderWire.body(wire)["input"].array ?? []
            let replay = input.filter { item in native.contains { $0["id"] == item["id"] && item["id"] != .null } }
            guard replay == native else {
                throw ChatGPTServiceError(status: 400, body: .object(["error": .object(["code": "invalid_request_error", "param": "input"])]))
            }
            if ProcessInfo.processInfo.arguments.contains("--chatgpt-request-error-fixtures") {
                try await Task.sleep(for: .seconds(8)); try Task.checkCancellation()
                throw ChatGPTServiceError(status: 400, body: .object(["error": .object(["code": "invalid_request_error", "param": "input", "message": "synthetic-secret-never-display"])]))
            }
            output.yield(.text("Repository audit completed with partial tool coverage. Narrow the file paths for a deeper review."))
            output.yield(.usage(Usage(input: 3577, output: 35))); output.yield(.finish("stop")); return
        }
        output.yield(.reasoning("Reviewing the repository map and file list before choosing narrower paths."))
        output.yield(.text("Inspecting the repository.\n\n"))
        var frames: [JSON] = []
        for (index, item) in native.enumerated() {
            frames.append(.object(["type": "response.output_item.done", "output_index": .number(Double(index)), "item": item]))
        }
        frames.append(.object(["type": "response.completed", "response": .object(["output": .array(native)])]))
        let encoder = JSONEncoder(); var bytes = Data()
        for frame in frames {
            bytes.append(Data("data: ".utf8)); bytes.append(try encoder.encode(frame)); bytes.append(Data("\n\n".utf8))
        }
        var parser = SSEParser(), decoder = ProviderEventDecoder(format: .responses)
        for frame in try parser.feed(bytes, final: true) {
            for event in try decoder.decode(frame) { output.yield(event) }
        }
    }
    private static func replyStability(_ request: RunRequest, output: AsyncThrowingStream<ChatEvent, Error>.Continuation) async throws {
        let lastUser = request.messages.lastIndex(where: { $0.role == .user }) ?? 0
        let rounds = request.messages.suffix(from: lastUser).filter { $0.role == .tool }.count
        let summaries = ["First reasoning summary remains visible.",
                         "Second reasoning summary is retained across the tool round.",
                         "Final reasoning summary is retained after completion."]
        output.yield(.reasoning(summaries[min(rounds, 2)]))
        try await Task.sleep(for: .seconds(3)); try Task.checkCancellation()
        if rounds == 0 {
            output.yield(.text("## Stable reply\n\nThe initial findings stay visible throughout the audit.\n\n"))
        } else if rounds == 1 {
            output.yield(.text("The next round adds detail without clearing earlier findings.\n\n"))
        } else {
            output.yield(.text("The audit is complete.")); output.yield(.finish("stop")); return
        }
        try await Task.sleep(for: .seconds(3)); try Task.checkCancellation()
        output.yield(.tool(ToolCall(id: "fixture-read-\(rounds)", name: "read_file", arguments: .object(["path": "README.md"]))))
        output.yield(.finish("tool_calls"))
    }
}

/// Exercises the actual ChatGPT client with in-memory synthetic credentials and
/// packet-sized bursts. No network, Keychain account or billing path is used.
private enum DevelopmentResponseStream {
    static func stream(_ original: RunRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        do {
            var request = original
            let account: JSON = .object(["clientID":"oaiapp_fixture","subject":"rapid-stream-fixture"])
            request.profile.authentication = .chatGPT
            request.profile.chatGPTAccount = try JSONDecoder().decode(ChatGPTAccount.self, from: account.encoded)
            let record: JSON = .object(["clientID":"oaiapp_fixture","account":account,"accessToken":"synthetic-rapid-stream-access","idToken":"synthetic-id",
                "scopes":.array(ChatGPTAuth.scopes.split(separator:" ").map { .string(String($0)) }),
                "expiresAt":.number(Date().addingTimeInterval(3600).timeIntervalSinceReferenceDate)])
            let secrets = DevelopmentStreamSecrets(key:"chatgpt:profile:\(request.profile.id.uuidString)",value:record.encoded)
            let wire = DevelopmentResponseTransport()
            return ChatGPTProviderClient(connections:ChatGPTConnectionStore(secrets:secrets,transport:wire),transport:wire).stream(request)
        } catch { return AsyncThrowingStream { $0.finish(throwing:ProviderFailure.safe(error)) } }
    }
}
private final class DevelopmentStreamSecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String:Data]
    init(key:String,value:Data) { values = [key:value] }
    func read(_ account:String,synchronizable:Bool) throws -> Data? { lock.withLock { values[account] } }
    func write(_ value:Data,account:String,synchronizable:Bool) throws { lock.withLock { values[account] = value } }
    func delete(_ account:String,synchronizable:Bool) throws { lock.withLock { values[account] = nil } }
}
private struct DevelopmentResponseTransport: HTTPTransport {
    func send(_ request:URLRequest,limit:Int) async throws -> HTTPResult { throw RMError.unsupported }
    func stream(_ request:URLRequest,limit:Int) -> AsyncThrowingStream<Data,Error> { AsyncThrowingStream { $0.finish(throwing:RMError.unsupported) } }
    func streamResponse(_ request:URLRequest,limit:Int) -> AsyncThrowingStream<HTTPStreamEvent,Error> {
        AsyncThrowingStream { output in
            let task = Task {
                func frame(_ value:JSON) throws -> Data { Data("data: ".utf8)+(try JSONEncoder().encode(value))+Data("\n\n".utf8) }
                do {
                    output.yield(.response(status:200,headers:[:]))
                    if DevelopmentFixtures.emptyResponse {
                        output.yield(.data(try frame(.object(["type":"response.completed","response":.object(["output":.array([]),"usage":.object(["input_tokens":904,"output_tokens":16])])]))))
                        output.finish(); return
                    }
                    if DevelopmentFixtures.completedResponses {
                        let input = try JSON.parse(request.httpBody ?? Data())["input"].array ?? []
                        let turn = input.lastIndex(where:{ $0["role"].string == "user" }) ?? 0
                        let hasRead = input.dropFirst(turn).contains { $0["type"].string == "function_call_output" }
                        if hasRead {
                            let summary:JSON = .object(["type":"reasoning","id":.string("rs_completed_\(turn)"),"encrypted_content":"synthetic-completed-summary","summary":.array([.object(["type":"summary_text","text":"Reviewed the README returned by the repository tool."])])])
                            let text = "# Repository audit complete\n\nInspected README.md on main. The repository introduces its purpose clearly; expand the setup and testing instructions for contributors. No files were changed."
                            let message:JSON = .object(["type":"message","id":.string("msg_completed_\(turn)"),"role":"assistant","phase":"final_answer","status":"completed","content":.array([.object(["type":"output_text","text":.string(text),"annotations":.array([])])])])
                            output.yield(.data(try frame(.object(["type":"response.output_item.done","output_index":0,"item":summary]))))
                            output.yield(.data(try frame(.object(["type":"response.output_item.done","output_index":1,"item":message]))))
                        } else {
                            let text = "I’ll review the repository for cleanup opportunities and UI/display improvements."
                            let message:JSON = .object(["type":"message","id":.string("msg_preamble_\(turn)"),"role":"assistant","phase":"commentary","status":"completed","content":.array([.object(["type":"output_text","text":.string(text),"annotations":.array([])])])])
                            let call:JSON = .object(["type":"function_call","id":.string("fc_read_\(turn)"),"call_id":.string("call_read_\(turn)"),"name":"read_file","namespace":"repo_manager","arguments":"{\"path\":\"README.md\"}","status":"completed"])
                            output.yield(.data(try frame(.object(["type":"response.output_text.delta","output_index":0,"content_index":0,"delta":.string(text)]))))
                            output.yield(.data(try frame(.object(["type":"response.output_item.done","output_index":0,"item":message]))))
                            output.yield(.data(try frame(.object(["type":"response.output_item.done","output_index":1,"item":call]))))
                        }
                        // Metadata-only completion must preserve all stream items.
                        output.yield(.data(try frame(.object(["type":"response.completed","response":.object(["output":.array([]),"usage":.object(["input_tokens":hasRead ? 904 : 881,"output_tokens":hasRead ? 16 : 50])])]))))
                        output.finish(); return
                    }
                    output.yield(.data(try frame(.object(["type":"response.reasoning_summary_text.delta","delta":"Reasoning stays visible while the repository response grows."]))))
                    var text = "# Streaming audit\n\n"
                    output.yield(.data(try frame(.object(["type":"response.output_text.delta","delta":.string(text)]))))
                    for index in 1...24 {
                        let paragraph = "Section \(index): The repository response arrives in small pieces. Earlier messages must remain readable while new content grows. Unicode text such as İstanbul 👩🏽‍💻 stays intact.\n\n"
                        var packet = Data()
                        for character in paragraph { packet += try frame(.object(["type":"response.output_text.delta","delta":.string(String(character))])) }
                        text += paragraph; output.yield(.data(packet))
                        try await Task.sleep(for:.milliseconds(600))
                    }
                    let ending = "# Audit complete\n\nThe streaming response completed without a connection alert."
                    text += ending; output.yield(.data(try frame(.object(["type":"response.output_text.delta","delta":.string(ending)]))))
                    let message:JSON = .object(["type":"message","id":"msg_rapid_fixture","role":"assistant","status":"completed","content":.array([.object(["type":"output_text","text":.string(text),"annotations":.array([])])])])
                    output.yield(.data(try frame(.object(["type":"response.completed","response":.object(["output":.array([message]),"usage":.object(["input_tokens":881,"output_tokens":100])])]))))
                    output.finish(throwing:RMError.connection) // A socket reset after the terminal event is harmless.
                } catch { output.finish(throwing:ProviderFailure.safe(error)) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
