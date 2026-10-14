import Foundation
import Testing
@testable import RepoManagerCore

@Suite struct GitHubPairingTests {
    @Test func publicConfigurationRequiresDedicatedIdentity() throws {
        #expect(throws:GitHubPairingError.configurationUnavailable) { try GitHubAppConfiguration(clientID:nil,appSlug:nil) }
        let config = try GitHubAppConfiguration(clientID:"Iv1.0000000000000001",appSlug:"repo-manager-test")
        #expect(config.installationURL.absoluteString == "https://github.com/apps/repo-manager-test/installations/new")
    }
    @Test(arguments:["", "Ov23likbAwZPky4GT7B5", "$(REPO_MANAGER_GITHUB_CLIENT_ID)", "Iv1.fixture", "Iv1.0000000000000001\n", "Iv1.PLACEHOLDER"])
    func invalidPublicIdentityCannotBeConfigured(_ value:String) {
        #expect(throws:GitHubPairingError.configurationUnavailable) { try GitHubAppConfiguration(clientID:value,appSlug:"repo-manager") }
    }
    @Test(arguments:["", "../private", "repo manager", "repo-manager?token=value", "RepoManager", "-repo-manager", "repo-manager-"])
    func installationDestinationCannotBeInjected(_ slug:String) {
        #expect(throws:GitHubPairingError.configurationUnavailable) { try GitHubAppConfiguration(clientID:"Iv1.0000000000000001",appSlug:slug) }
    }
    @Test func missingIdentityDoesNotMakeNetworkRequest() async throws {
        let f = try await FixtureServices.make()
        let before = await f.fixture.allRequests().count
        await #expect(throws:GitHubPairingError.configurationUnavailable) { try await f.connections.beginDeviceFlow(clientID:"") }
        #expect(await f.fixture.allRequests().count == before)
    }
    @Test(arguments:[
        ("access_denied",GitHubPairingError.denied),
        ("expired_token",GitHubPairingError.expired),
        ("device_flow_disabled",GitHubPairingError.deviceFlowDisabled),
        ("incorrect_client_credentials",GitHubPairingError.configurationUnavailable),
        ("incorrect_device_code",GitHubPairingError.rejected)
    ])
    func deviceAuthorizationErrorsHaveRecoveryStates(_ code:String,_ expected:GitHubPairingError) async throws {
        let f = try await FixtureServices.make()
        await f.fixture.configureOAuth([.object(["error":.string(code),"error_description":"upstream-sensitive-canary"])])
        let flow = try await f.connections.beginDeviceFlow(clientID:"Iv1.fixture")
        let connections = GitHubConnectionStore(vault:f.vault,secrets:f.secrets,transport:TestTransport { try await f.fixture.handle($0) },pollWait:{ _ in })
        await #expect(throws:expected) { try await connections.completeDeviceFlow(flow,clientID:"Iv1.fixture") }
        #expect(!expected.localizedDescription.contains("upstream-sensitive-canary"))
    }
    @Test(arguments:["https://evil.example/login/device", "https://github.com.evil.example/login/device", "https://github.com/login/oauth/authorize", "https://github.com/login/device?token=canary", "https://user:pass@github.com/login/device", "https://github.com:444/login/device", "https://github.com/login/device#fragment"])
    func authorizationBrowserOnlyReceivesValidatedGitHubURL(_ url:String) async throws {
        let f = try await FixtureServices.make()
        await f.fixture.configureDeviceResponse(.object(["device_code":"synthetic","user_code":"ABCD-EFGH","verification_uri":.string(url),"expires_in":600,"interval":1]))
        await #expect(throws:GitHubPairingError.invalidResponse) { try await f.connections.beginDeviceFlow(clientID:"Iv1.fixture") }
        #expect(await f.fixture.authCalls == 0)
    }
    @Test func disabledAuthorizationFailsBeforePolling() async throws {
        let f = try await FixtureServices.make()
        await f.fixture.configureDeviceResponse(.object(["error":"device_flow_disabled"]))
        await #expect(throws:GitHubPairingError.deviceFlowDisabled) { try await f.connections.beginDeviceFlow(clientID:"Iv1.fixture") }
        #expect(await f.fixture.authCalls == 0)
    }
    @Test func requestedSlowdownAndPublicClientIDAreHonoredWithoutClientSecret() async throws {
        let f = try await FixtureServices.make(),waits = PairingWaits()
        await f.fixture.configureOAuth([.object(["error":"slow_down","interval":12]),.object(["access_token":"synthetic-device-access"])])
        let connections = GitHubConnectionStore(vault:f.vault,secrets:f.secrets,transport:TestTransport { try await f.fixture.handle($0) },pollWait:{ await waits.record($0) })
        let flow = try await connections.beginDeviceFlow(clientID:"Iv1.fixture")
        _ = try await connections.completeDeviceFlow(flow,clientID:"Iv1.fixture")
        #expect(await waits.values == [1,12])
        let requests = await f.fixture.allRequests().filter { $0.url?.host == "github.com" }
        #expect(requests.count == 3)
        for request in requests {
            let body = String(decoding:request.httpBody ?? Data(),as:UTF8.self)
            #expect(body.contains("client_id=Iv1.fixture"))
            #expect(!body.contains("client_secret"))
            #expect(request.value(forHTTPHeaderField:"Authorization") == nil)
        }
    }
    @Test func backgroundCancellationRejectsLateDeviceResponse() async throws {
        let f = try await FixtureServices.make(),gate = PairingResponseGate()
        let transport = TestTransport { request in
            await gate.arriveAndWait()
            return try await f.fixture.handle(request)
        }
        let connections = GitHubConnectionStore(vault:f.vault,secrets:f.secrets,transport:transport)
        let task = Task { try await connections.beginDeviceFlow(clientID:"Iv1.fixture") }
        await gate.waitForArrival()
        await connections.cancelRequests()
        await gate.release()
        await #expect(throws:RMError.cancelled) { try await task.value }
        #expect(await connections.savedAccounts().isEmpty)
    }
    @Test func resumedSlowdownWaitCannotOutliveOriginalDeadline() async throws {
        let f = try await FixtureServices.make(),waits = PairingWaits()
        let connections = GitHubConnectionStore(vault:f.vault,secrets:f.secrets,transport:TestTransport { try await f.fixture.handle($0) },pollWait:{
            await waits.record($0); throw RMError.cancelled
        })
        let flow = DeviceAuthorization(userCode:"ABCD-EFGH",verificationURL:URL(string:"https://github.com/login/device")!,deviceCode:"synthetic",expires:Date().addingTimeInterval(30),interval:1800)
        let before = await f.fixture.allRequests().count
        await #expect(throws:RMError.cancelled) { try await connections.completeDeviceFlow(flow,clientID:"Iv1.fixture") }
        let delays = await waits.values
        #expect(delays.count == 1)
        #expect((1...30).contains(delays.first ?? 0))
        #expect(await f.fixture.allRequests().count == before)
    }
}

private actor PairingWaits {
    var values:[Int] = []
    func record(_ value:Int) { values.append(value) }
}
private actor PairingResponseGate {
    private var arrived = false
    private var arrivalWaiter:CheckedContinuation<Void,Never>?
    private var responseWaiter:CheckedContinuation<Void,Never>?
    func arriveAndWait() async {
        await withCheckedContinuation { continuation in
            responseWaiter = continuation; arrived = true; arrivalWaiter?.resume(); arrivalWaiter = nil
        }
    }
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }
    func release() { responseWaiter?.resume(); responseWaiter = nil }
}
