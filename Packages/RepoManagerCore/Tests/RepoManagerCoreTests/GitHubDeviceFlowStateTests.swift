import Foundation
import Testing
@testable import RepoManagerCore

@Suite struct GitHubDeviceFlowStateTests {
    private func flow(expires: Date = Date().addingTimeInterval(600)) -> DeviceAuthorization {
        DeviceAuthorization(userCode: "ABCD-EFGH", verificationURL: URL(string: "https://github.com/login/device")!,
                            deviceCode: "synthetic-device-code", expires: expires, interval: 5)
    }
    @Test func safariReturnKeepsTheCodeAndOriginalDeadline() throws {
        var state = GitHubDeviceFlowState()
        let ticket = state.begin(), code = flow()
        let received = state.receive(code, ticket: ticket); #expect(received)
        state.suspend()
        #expect(state.phase == .suspended)
        let continuation = try state.resume(); let resumed = try #require(continuation)
        #expect(resumed.1 == code)
        #expect(resumed.0 != ticket)
        #expect(state.phase == .waiting)
    }
    @Test func oldForegroundResponseCannotCompleteAResumedAttempt() throws {
        var state = GitHubDeviceFlowState()
        let ticket = state.begin()
        let received = state.receive(flow(), ticket: ticket); #expect(received)
        state.suspend()
        let continuation = try state.resume(); let resumed = try #require(continuation)
        let staleCompletion = state.complete(ticket: ticket); #expect(!staleCompletion)
        #expect(state.authorization != nil)
        let completion = state.complete(ticket: resumed.0); #expect(completion)
        #expect(state.authorization == nil)
    }
    @Test func explicitCancelCannotResumeFromSafari() throws {
        var state = GitHubDeviceFlowState()
        let ticket = state.begin()
        let received = state.receive(flow(), ticket: ticket); #expect(received)
        state.suspend(); state.cancel()
        let resumed = try state.resume(); #expect(resumed == nil)
        #expect(state.authorization == nil)
        let staleCompletion = state.complete(ticket: ticket); #expect(!staleCompletion)
    }
    @Test func expiryDoesNotMintANewDeadline() throws {
        var state = GitHubDeviceFlowState()
        let now = Date(), ticket = state.begin()
        let received = state.receive(flow(expires: now.addingTimeInterval(5)), ticket: ticket); #expect(received)
        state.suspend()
        #expect(throws: GitHubPairingError.expired) { try state.resume(at: now.addingTimeInterval(6)) }
        #expect(state.authorization == nil)
        #expect(state.phase == .idle)
    }
    @Test func interruptedInitialRequestCannotShowALateCode() {
        var state = GitHubDeviceFlowState()
        let ticket = state.begin()
        state.suspend()
        let received = state.receive(flow(), ticket: ticket); #expect(!received)
        #expect(state.authorization == nil)
    }
    @Test func githubSlowDownSurvivesBrowserHandoff() throws {
        var state = GitHubDeviceFlowState()
        let ticket = state.begin()
        let received = state.receive(flow(), ticket: ticket); #expect(received)
        state.updateInterval(65, ticket: ticket)
        state.suspend()
        let resumed = try state.resume(); #expect(resumed?.1.interval == 65)
    }
}
