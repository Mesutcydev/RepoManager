import Foundation
import RepoManagerCore

enum DevelopmentFixtures {
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
        enabled && (ProcessInfo.processInfo.arguments.contains("--repository-fixtures") || githubPairing)
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
        else if path == "/repositories/42" || path == "/repos/preview-maintainer/repo-manager" { json = .object(["id":42,"full_name":"preview-maintainer/repo-manager","permissions":.object(["pull":true,"push":true,"admin":false])]) }
        else if path.contains("/git/ref/") { json = .object(["object":.object(["sha":.string(sha)])]) }
        else if path.contains("/git/commits/") { json = .object(["sha":.string(sha),"tree":.object(["sha":.string(sha)]),"parents":.array([])]) }
        else if path.contains("/git/trees/") { json = .object(["truncated":false,"tree":.array([.object(["path":"README.md","type":"blob","mode":"100644","sha":.string(sha),"size":128])])]) }
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
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    output.yield(.reasoning("Checking the selected conversation and its available tools."))
                    try await Task.sleep(for:.milliseconds(350)); try Task.checkCancellation()
                    if !request.messages.contains(where:{ $0.role == .tool }), request.messages.last?.text.contains("calculator") == true {
                        output.yield(.tool(ToolCall(id:"fixture-calculator",name:"calculator",arguments:.object(["expression":"2+2"])))); output.yield(.finish("tool_calls")); output.finish(); return
                    }
                    let words = "This is a synthetic streaming response for native interface verification. It exercises reasoning timing, stable message identity, follow scrolling, the composer, and cancellation through the production run coordinator. Your draft and reading position stay with the conversation.".split(separator:" ")
                    for word in words { try Task.checkCancellation(); output.yield(.text(String(word)+" ")); try await Task.sleep(for:.milliseconds(140)) }
                    output.yield(.usage(Usage(input:42,output:35))); output.yield(.finish("stop")); output.finish()
                } catch { output.finish(throwing:RMError.cancelled) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
