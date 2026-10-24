import Foundation
import Testing
@testable import RepoManagerCore

final class TestSecrets: SecretStore, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String:Data] = [:]
    var locked = false
    func read(_ account: String, synchronizable: Bool) throws -> Data? { try lock.withLock { if locked { throw RMError.locked }; return values["\(synchronizable):\(account)"] } }
    func write(_ value: Data, account: String, synchronizable: Bool) throws { try lock.withLock { if locked { throw RMError.locked }; values["\(synchronizable):\(account)"] = value } }
    func delete(_ account: String, synchronizable: Bool) throws { try lock.withLock { if locked { throw RMError.locked }; values["\(synchronizable):\(account)"] = nil } }
}
struct TestTransport: HTTPTransport {
    var handler: @Sendable (URLRequest) async throws -> HTTPResult
    func send(_ request: URLRequest, limit: Int) async throws -> HTTPResult { let r = try await handler(request); guard r.data.count <= limit else { throw RMError.tooLarge }; return r }
    func stream(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<Data,Error> {
        AsyncThrowingStream { c in let task = Task { do { let r = try await send(request,limit:limit); try SecureHTTPTransport.checkStatus(r.status); for byte in r.data { try Task.checkCancellation(); c.yield(Data([byte])) }; c.finish() } catch { c.finish(throwing:error) } }; c.onTermination = { _ in task.cancel() } }
    }
}
struct TestAuthenticator: NativeAuthenticator { var accepts = true; func authenticate(action: String, target: String) async throws -> Bool { accepts } }
func temporaryRoot() throws -> URL { let url = FileManager.default.temporaryDirectory.appendingPathComponent("RMTests-"+UUID().uuidString); try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url }
func response(_ json: JSON, _ status: Int = 200) -> HTTPResult { HTTPResult(status:status,data:json.encoded,headers:[:]) }
let baseSHA = String(repeating:"a",count:40), nextSHA = String(repeating:"b",count:40), treeSHA = String(repeating:"c",count:40), blobSHA = String(repeating:"d",count:40)

actor GitHubFixture {
    var head = baseSHA; var requests: [URLRequest] = []; var uncertain = false
    var content = "one\ntwo\n"; var mode = "100755"; var permission = true; var offline = false
    var createdRepositories: [String:JSON] = [:]
    var statusOverride:Int?
    var secretPublicKey:String?
    var treeEntries: [JSON]?
    var oauthResponses: [JSON] = []; var authCalls = 0
    var deviceResponse: JSON?
    func advance() { head = nextSHA }
    func setUncertain() { uncertain = true }
    func setOffline(_ value:Bool) { offline = value }
    func setStatus(_ value:Int?) { statusOverride = value }
    func setPermission(_ value:Bool) { permission = value }
    func setSecretPublicKey(_ value:String) { secretPublicKey = value }
    func configureTree(_ entries: [JSON]) { treeEntries = entries }
    func configureOAuth(_ responses: [JSON]) { oauthResponses = responses }
    func configureDeviceResponse(_ value:JSON) { deviceResponse = value }
    func allRequests() -> [URLRequest] { requests }
    func writes() -> [URLRequest] { requests.filter { ($0.httpMethod ?? "GET") != "GET" && $0.url?.host == "api.github.com" } }
    func handle(_ request: URLRequest) throws -> HTTPResult {
        requests.append(request)
        let path = request.url!.path; let method = request.httpMethod ?? "GET"
        if offline { throw RMError.connection }
        if path == "/login/device/code" { return response(deviceResponse ?? .object(["device_code":"fixture-device-code","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device","expires_in":600,"interval":1])) }
        if path == "/login/oauth/access_token" { authCalls += 1; return response(oauthResponses.isEmpty ? .object(["error":"access_denied"]) : oauthResponses.removeFirst()) }
        if path == "/user" { return response(.object(["id":7,"login":"maintainer"])) }
        if path == "/user/repos",method == "POST" {
            if uncertain { throw RMError.connection }
            let body = try JSON.parse(request.httpBody ?? Data()); let name = body["name"].string ?? ""
            let info:JSON = .object(["id":100,"full_name":.string("maintainer/"+name),"private":body["private"],"default_branch":"main"])
            createdRepositories["/repos/maintainer/"+name] = info; return response(info,201)
        }
        if path.hasPrefix("/repos/maintainer/"),path.split(separator:"/").count == 3,path != "/repos/maintainer/demo" { return createdRepositories[path].map { response($0) } ?? response(.object([:]),404) }
        if path == "/repositories/42" || path == "/repos/maintainer/demo" { return response(.object(["id":42,"full_name":"maintainer/demo","permissions":.object(["pull":true,"push":.bool(permission),"admin":.bool(permission)])])) }
        if method == "GET",path.hasSuffix("/secrets/public-key"),let secretPublicKey { return response(.object(["key_id":"fixture-key","key":.string(secretPublicKey)])) }
        if method == "GET",path.contains("/secrets/"),!path.hasSuffix("/public-key") { return response(.object([:]),404) }
        if path.contains("/git/ref/heads/") { return response(.object(["object":.object(["sha":.string(head)])])) }
        if method == "GET", path.contains("/git/commits/") { return response(.object(["sha":.string(baseSHA),"tree":.object(["sha":.string(treeSHA)]),"parents":.array([.object(["sha":.string(nextSHA)])])])) }
        if method == "GET", path.contains("/git/trees/") { return response(.object(["truncated":false,"tree":.array(treeEntries ?? [.object(["path":"script.sh","type":"blob","mode":.string(mode),"sha":.string(blobSHA),"size":.number(Double(content.utf8.count))])])])) }
        if method == "GET", path.contains("/git/blobs/") { return response(.object(["encoding":"base64","content":.string(Data(content.utf8).base64EncodedString())])) }
        if method != "GET" {
            if uncertain { throw RMError.connection }
            if let statusOverride { return response(.object(["id":1,"state":"queued"]),statusOverride) }
            if path.hasSuffix("/git/blobs") { return response(.object(["sha":.string(blobSHA)]),201) }
            if path.hasSuffix("/git/trees") { return response(.object(["sha":.string(treeSHA)]),201) }
            if path.hasSuffix("/git/commits") { return response(.object(["sha":.string(nextSHA)]),201) }
            if path.contains("/git/refs/heads/") { head = nextSHA; return response(.object(["object":.object(["sha":.string(head)])])) }
            return response(.object(["id":1,"title":"Fixture","state":"open"]),method == "DELETE" ? 204 : 200)
        }
        return response(.array([.object(["id":1,"number":1,"title":"Fixture","state":"open"])]))
    }
}
struct FixtureServices: Sendable {
    let secrets: TestSecrets; let vault: SecureStore; let fixture: GitHubFixture; let connections: GitHubConnectionStore
    let github: GitHubClient; let approvals: ApprovalCoordinator; let workspace: GitHubWorkspace; let tools: ToolRegistry; let scope: RepositoryScope
    static func make(authenticates: Bool = true,authenticator:(any NativeAuthenticator)? = nil) async throws -> FixtureServices {
        let secrets = TestSecrets(), fixture = GitHubFixture()
        let transport = TestTransport { try await fixture.handle($0) }
        let vault = try SecureStore(root:temporaryRoot(),secrets:secrets)
        let connections = GitHubConnectionStore(vault:vault,secrets:secrets,transport:transport)
        let account = try await connections.connectPAT("github_pat_"+String(repeating:"f",count:40))
        let scope = RepositoryScope(accountID:account.id,connectionID:account.connectionID,repositoryID:42,owner:"maintainer",name:"demo",branch:"main")
        let github = GitHubClient(connections:connections,vault:vault,transport:transport)
        let approvals = ApprovalCoordinator(github:github,vault:vault,authenticator:authenticator ?? TestAuthenticator(accepts:authenticates))
        let workspace = GitHubWorkspace(github:github,vault:vault,approvals:approvals)
        let tools = ToolRegistry(github:github,workspace:workspace,approvals:approvals,knowledge:LexicalKnowledge(vault:vault),web:WebTools(transport:transport,secrets:secrets))
        return FixtureServices(secrets:secrets,vault:vault,fixture:fixture,connections:connections,github:github,approvals:approvals,workspace:workspace,tools:tools,scope:scope)
    }
}
struct EventProvider: ProviderClient {
    var events: [ChatEvent]
    func stream(_ request: RunRequest) -> AsyncThrowingStream<ChatEvent,Error> { AsyncThrowingStream { c in for e in events { c.yield(e) }; c.finish() } }
}
