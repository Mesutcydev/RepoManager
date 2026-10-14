import XCTest
import Foundation
import Security
import RepoManagerCore

final class TLSAndKeychainTests:XCTestCase {
    @MainActor func testSignedHostKeychainAndHTTPSListener() async throws {
        let namespace = "com.mesutcydev.repomanager.securitytests."+UUID().uuidString
        let secrets = KeychainStore(service:namespace)
        defer { try? secrets.wipeOwnedItems(includingSynchronizable:true) }
        let credentialCanary = Data("synthetic-keychain-only-fixture".utf8)
        try secrets.write(credentialCanary,account:"fixture")
        XCTAssertEqual(try secrets.read("fixture"),credentialCanary)
        var attributes:CFTypeRef?
        let status = SecItemCopyMatching([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:namespace,
            kSecAttrAccount as String:"fixture",kSecReturnAttributes as String:true,kSecUseDataProtectionKeychain as String:true] as CFDictionary,&attributes)
        XCTAssertEqual(status,errSecSuccess)
        let values = try XCTUnwrap(attributes as? [String:Any])
        XCTAssertEqual(values[kSecAttrAccessible as String] as? String,kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(values[kSecAttrSynchronizable as String] as? Bool,false)
        try secrets.write(Data("synthetic-history-key".utf8),account:"history-fixture",synchronizable:true)
        try secrets.wipeOwnedItems()
        XCTAssertNil(try secrets.read("fixture"))
        XCTAssertEqual(try secrets.read("history-fixture",synchronizable:true),Data("synthetic-history-key".utf8),"Local wipe must retain the shared history key")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(namespace,isDirectory:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let vault = try SecureStore(root:root,secrets:secrets), transport = FixtureOnlyHTTP()
        let accounts = GitHubConnectionStore(vault:vault,secrets:secrets,transport:transport)
        let github = GitHubClient(connections:accounts,vault:vault,transport:transport)
        let approvals = ApprovalCoordinator(github:github,vault:vault,authenticator:RefuseAuthentication())
        let workspace = GitHubWorkspace(github:github,vault:vault,approvals:approvals)
        let tools = ToolRegistry(github:github,workspace:workspace,approvals:approvals,knowledge:LexicalKnowledge(vault:vault),web:WebTools(transport:transport,secrets:secrets))
        let auth = APIAuthorization(vault:vault,secrets:secrets)
        var profile = ProviderProfile(preset:.openAI); profile.consentEndpoint = profile.endpoint; profile.models = [ModelMetadata(id:"fixture")]
        let grant = APIClientGrant(name:"signed-host-fixture",providerIDs:[profile.id],repository:nil,tools:[])
        let credential = try await auth.create(grant)
        let runs = RunCoordinator(provider:RefuseProvider(),tools:tools,approvals:approvals)
        let api = AgentAPI(auth:auth,runs:runs,tools:tools,approvals:approvals); await api.configure(profiles:[profile])
        let identity = TLSIdentity(namespace:namespace+".tls"), server = HTTPSServer(api:api,identity:identity)
        do {
            let material = try await server.start(host:"127.0.0.1",port:13435)
            let restored = try identity.loadOrCreate(host:"127.0.0.1")
            XCTAssertEqual(material.fingerprint,restored.fingerprint,"Restore must reuse the same Keychain identity")
            XCTAssertTrue(identity.valid(material.certificate,host:"127.0.0.1"))
            XCTAssertFalse(identity.valid(material.certificate,host:"different.example"))
            let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.urlCredentialStorage = nil; config.httpCookieStorage = nil; config.timeoutIntervalForRequest = 5
            let client = URLSession(configuration:config,delegate:TrustedFixtureCertificate(certificate:material.certificate),delegateQueue:nil)
            defer { client.invalidateAndCancel() }
            func request(_ token:String?) async throws -> Int {
                var request = URLRequest(url:URL(string:"https://127.0.0.1:13435/v1/models")!)
                if let token { request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization") }
                let (_,response) = try await client.data(for:request); return try XCTUnwrap(response as? HTTPURLResponse).statusCode
            }
            let unauthenticated = try await request(nil); XCTAssertEqual(unauthenticated,401)
            let authenticated = try await request(credential); XCTAssertEqual(authenticated,200)
            try await api.revokeClient(grant.id)
            let revoked = try await request(credential); XCTAssertEqual(revoked,401)
            await server.stop(); try identity.removeOwned()
        } catch { await server.stop(); try? identity.removeOwned(); throw error }
    }
}
private struct FixtureOnlyHTTP:HTTPTransport {
    func send(_ request:URLRequest,limit:Int) async throws -> HTTPResult { throw RMError.forbidden }
    func stream(_ request:URLRequest,limit:Int) -> AsyncThrowingStream<Data,Error> { AsyncThrowingStream { $0.finish(throwing:RMError.forbidden) } }
}
private struct RefuseProvider:ProviderClient {
    func stream(_ request:RunRequest) -> AsyncThrowingStream<ChatEvent,Error> { AsyncThrowingStream { $0.finish(throwing:RMError.forbidden) } }
}
private struct RefuseAuthentication:NativeAuthenticator {
    func authenticate(action:String,target:String) async throws -> Bool { false }
}
private final class TrustedFixtureCertificate:NSObject,URLSessionDelegate,@unchecked Sendable {
    let certificate:Data
    init(certificate:Data) { self.certificate = certificate }
    func urlSession(_ session:URLSession,didReceive challenge:URLAuthenticationChallenge,completionHandler:@escaping (URLSession.AuthChallengeDisposition,URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,let certificate = SecCertificateCreateWithData(nil,certificate as CFData) else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        SecTrustSetAnchorCertificates(trust,[certificate] as CFArray); SecTrustSetAnchorCertificatesOnly(trust,true); SecTrustSetNetworkFetchAllowed(trust,false)
        guard SecTrustSetPolicies(trust,SecPolicyCreateSSL(true,challenge.protectionSpace.host as CFString)) == errSecSuccess,
              SecTrustEvaluateWithError(trust,nil) else { completionHandler(.cancelAuthenticationChallenge,nil); return }
        completionHandler(.useCredential,URLCredential(trust:trust))
    }
}
