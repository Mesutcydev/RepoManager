import Foundation
import Testing
@testable import RepoManagerCore

private actor WaitingAuthentication:NativeAuthenticator {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void,Never>] = []
    private var releaseWaiter:CheckedContinuation<Bool,Never>?
    func authenticate(action:String,target:String) async throws -> Bool {
        started = true; for waiter in startWaiters { waiter.resume() }; startWaiters.removeAll()
        return await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitForStart() async { if !started { await withCheckedContinuation { startWaiters.append($0) } } }
    func release() { releaseWaiter?.resume(returning:true); releaseWaiter = nil }
}

@Suite struct ManagementAcceptance {
    @Test func accountScopedFirstRepositoryCreationAndChangedScope() async throws {
        let f = try await FixtureServices.make(); let id = UUID()
        let account = try #require(await f.connections.savedAccounts().first)
        let args:JSON = .object(["body":.object(["name":"first-project","private":true,"auto_init":true])])
        let first = try await f.approvals.prepareRepositoryCreation(account:account,arguments:args,conversationID:id)
        #expect(first.scope.fullName == "maintainer/first-project"); #expect(first.before["exists"].bool == false)
        #expect(await f.fixture.writes().isEmpty)
        await f.approvals.bind(id,scope:f.scope)
        await #expect(throws:RMError.staleReview) { try await f.approvals.confirm(first.id) }
        let second = try await f.approvals.prepareRepositoryCreation(account:account,arguments:args,conversationID:id,initiatingScope:f.scope)
        let receipt = try await f.approvals.confirm(second.id)
        #expect(receipt.result["id"].int == 100); #expect(receipt.state == .completed)
        #expect(await f.fixture.writes().count == 1)
        await #expect(throws:RMError.conflict) { try await f.approvals.prepareRepositoryCreation(account:account,arguments:args,conversationID:id,initiatingScope:f.scope) }
    }
    @Test func cancellationDuringAuthenticationNeverStartsWrite() async throws {
        let authenticator = WaitingAuthentication(); let f = try await FixtureServices.make(authenticator:authenticator); let id = UUID()
        await f.approvals.bind(id,scope:f.scope)
        let plan = try await f.approvals.prepare(ToolCatalog.named("delete_repository"),arguments:.object([:]),scope:f.scope,conversationID:id)
        let confirmation = Task { try await f.approvals.confirm(plan.id,typedRepositoryName:f.scope.fullName) }
        await authenticator.waitForStart(); await f.approvals.invalidate(conversationID:id); await authenticator.release()
        do { _ = try await confirmation.value; Issue.record("Cancelled confirmation completed") } catch { }
        #expect(await f.fixture.writes().isEmpty); #expect(await f.approvals.pending().isEmpty)
    }
    @Test func asyncAcceptanceAndUncertainTargetInspection() async throws {
        let f = try await FixtureServices.make(); let id = UUID(); await f.approvals.bind(id,scope:f.scope)
        let definition = try ToolCatalog.named("cancel_workflow")
        let plan = try await f.approvals.prepare(definition,arguments:.object(["id":1]),scope:f.scope,conversationID:id)
        await f.fixture.setStatus(202)
        let receipt = try await f.approvals.confirm(plan.id); #expect(receipt.state == .accepted)
        await f.fixture.setStatus(nil)
        let uncertain = try await f.approvals.prepare(ToolCatalog.named("edit_issue"),arguments:.object(["id":1,"body":.object(["title":"A specific change"])]),scope:f.scope,conversationID:id)
        await f.fixture.setUncertain()
        await #expect(throws:RMError.uncertainWrite) { try await f.approvals.confirm(uncertain.id) }
        let count = await f.fixture.writes().count
        let observed = try await f.approvals.reconciliation(uncertain.id)
        #expect(observed["target"] != .null); #expect(observed["reviewed_arguments"]["body"]["title"].string == "A specific change")
        #expect(await f.fixture.writes().count == count); #expect(await f.approvals.journal().last?.state == .uncertain)
    }
    @Test func offlineCacheIsConnectionBoundAndNeverAuthorizesWrites() async throws {
        let f = try await FixtureServices.make(); let id = UUID(); await f.approvals.bind(id,scope:f.scope)
        _ = try await f.workspace.open(f.scope,conversationID:id)
        _ = try await f.workspace.read("script.sh",scope:f.scope,conversationID:id)
        await f.fixture.setOffline(true)
        #expect(try await f.workspace.read("script.sh",scope:f.scope,conversationID:id).updated != nil)
        await #expect(throws:RMError.connection) { try await f.approvals.prepare(ToolCatalog.named("create_issue"),arguments:.object(["body":.object(["title":"Offline change"])]),scope:f.scope,conversationID:id) }
        var other = f.scope; other.connectionID = UUID()
        await #expect(throws:RMError.authentication) { try await f.github.verify(other,allowOffline:true) }
        #expect(await f.fixture.writes().isEmpty)
    }
    @Test func backgroundRefreshUsesOnlyThreeExplicitCurrentScopes() {
        var data = AppData(); let account = GitHubAccount(id:1,login:"owner"); data.accounts = [account]
        for i in 1...6 {
            var c = Conversation(); c.repository = RepositoryScope(accountID:1,connectionID:i == 6 ? UUID() : account.connectionID,repositoryID:Int64(i),owner:"owner",name:"r\(i)",branch:"main")
            data.conversations.append(c)
        }
        #expect(BackgroundRefreshPolicy.scopes(data).isEmpty)
        data.preferences.backgroundNetworkRefresh = true
        let scopes = BackgroundRefreshPolicy.scopes(data)
        #expect(scopes.count == 3); #expect(scopes.allSatisfy { $0.connectionID == account.connectionID })
        data.conversations[4].archived = true
        #expect(!BackgroundRefreshPolicy.scopes(data).contains { $0.repositoryID == 5 })
    }
}
