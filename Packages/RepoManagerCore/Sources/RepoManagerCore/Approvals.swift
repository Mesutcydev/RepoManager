import Foundation

public protocol NativeAuthenticator: Sendable { func authenticate(action: String, target: String) async throws -> Bool }
/// Fails closed until the app injects its LocalAuthentication adapter.
public struct UnavailableAuthenticator: NativeAuthenticator {
    public init() {}
    public func authenticate(action: String, target: String) async throws -> Bool { throw RMError.unavailable }
}
public actor ApprovalCoordinator {
    private let github: GitHubClient; private let vault: SecureStore; private let authenticator: any NativeAuthenticator
    private var plans: [UUID:MutationPlan] = [:]; private var bindings: [UUID:RepositoryScope] = [:]
    private var consuming = Set<UUID>(); private var receipts: [MutationReceipt] = []
    private var repositoryWrites = Set<Int64>()
    private var draftRevisions: [UUID:UUID] = [:]
    private var confirmations: [UUID:Task<MutationReceipt,Error>] = [:]
    private var preparationEpoch:UInt64 = 0
    private let now:@Sendable () -> Date
    public init(github: GitHubClient, vault: SecureStore, authenticator: any NativeAuthenticator = UnavailableAuthenticator(),now:@escaping @Sendable () -> Date = { Date() }) {
        self.github = github; self.vault = vault; self.authenticator = authenticator; self.now = now
    }
    public func restoreJournal() async throws {
        receipts = try await vault.load([MutationReceipt].self,id:"operation-journal") ?? []
        for i in receipts.indices where receipts[i].state == .executing { receipts[i].state = .uncertain }
        try await vault.save(receipts,id:"operation-journal")
    }
    public func bind(_ conversationID: UUID, scope: RepositoryScope?) {
        if bindings[conversationID] != scope { invalidate(conversationID:conversationID) }; bindings[conversationID] = scope
    }
    public func draftChanged(_ id: UUID, revision: UUID) {
        if draftRevisions[id] != revision { invalidate(conversationID:id) }; draftRevisions[id] = revision
    }
    public func invalidate(conversationID: UUID) {
        preparationEpoch &+= 1
        for plan in plans.values where plan.conversationID == conversationID { confirmations[plan.id]?.cancel() }
        plans = plans.filter { $0.value.conversationID != conversationID }
    }
    public func invalidateAll() { preparationEpoch &+= 1; for task in confirmations.values { task.cancel() }; plans.removeAll() }
    public func pending(conversationID: UUID? = nil) -> [MutationPlan] {
        plans.values.filter { $0.expires > now() && (conversationID == nil || $0.conversationID == conversationID) }.sorted { $0.created < $1.created }
    }
    public func journal() -> [MutationReceipt] { receipts }
    public func prepare(_ definition: ToolDefinition, arguments: JSON, scope: RepositoryScope, conversationID: UUID, native: Bool = false) async throws -> MutationPlan {
        let lease = preparationEpoch
        guard definition.risk == .mutation || definition.risk == .consequential || definition.risk == .destructive,
              !definition.nativeOnly || native else { throw RMError.forbidden }
        try Schema.validate(arguments,against:definition.schema)
        try validateBody(definition,arguments:arguments)
        if definition.name == "create_repository" {
            guard bindings[conversationID] == scope,
                  let account = await github.connections.savedAccounts().first(where:{ $0.id == scope.accountID && $0.connectionID == scope.connectionID }) else { throw RMError.staleReview }
            try Task.checkCancellation(); guard lease == preparationEpoch else { throw RMError.staleReview }
            return try await prepareRepositoryCreation(account:account,arguments:arguments,conversationID:conversationID,initiatingScope:scope)
        }
        if definition.name == "upload_release_asset" {
            guard let id = UUID(uuidString:arguments["asset_id"].string ?? ""), let asset = try await vault.asset(id), asset.ownerID == conversationID else { throw RMError.forbidden }
        }
        guard bindings[conversationID] == scope,lease == preparationEpoch else { throw RMError.staleReview }
        guard !receipts.contains(where:{ $0.scope.repositoryID == scope.repositoryID && [.uncertain,.executing].contains($0.state) }) else { throw RMError.uncertainWrite }
        let before = try await github.remoteSnapshot(definition,arguments:arguments,scope:scope)
        let head = try await github.head(scope)
        try Task.checkCancellation()
        guard bindings[conversationID] == scope,lease == preparationEpoch else { throw RMError.staleReview }
        let plan = MutationPlan(scope:scope,conversationID:conversationID,operation:definition.name,arguments:arguments,before:GitHubRedaction.clean(before),
            expectedRemoteDigest:RecordCrypto.digest(before.encoded),expectedHead:head,risk:definition.risk)
        plans[plan.id] = plan; return plan
    }
    public func prepareRepositoryCreation(account:GitHubAccount,arguments:JSON,conversationID:UUID,initiatingScope:RepositoryScope? = nil) async throws -> MutationPlan {
        let lease = preparationEpoch
        let definition = try ToolCatalog.named("create_repository")
        try Schema.validate(arguments,against:definition.schema); try validateBody(definition,arguments:arguments)
        guard bindings[conversationID] == initiatingScope else { throw RMError.staleReview }
        let name = try InputValidation.component(arguments["body"]["name"].string ?? "")
        let scope = RepositoryScope(accountID:account.id,connectionID:account.connectionID,repositoryID:0,owner:account.login,name:name,branch:"main")
        guard !receipts.contains(where:{ $0.scope.accountID == account.id && $0.operation == "create_repository" && [.executing,.uncertain].contains($0.state) }) else { throw RMError.uncertainWrite }
        let snapshot = try await github.creationSnapshot(scope)
        try Task.checkCancellation(); guard lease == preparationEpoch else { throw RMError.staleReview }
        var plan = MutationPlan(scope:scope,conversationID:conversationID,operation:definition.name,arguments:arguments,before:snapshot,
            expectedRemoteDigest:RecordCrypto.digest(snapshot.encoded),expectedHead:"",risk:.consequential)
        plan.accountCreation = true; plan.initiatingScope = initiatingScope
        try validate(plan.id,candidate:plan); plans[plan.id] = plan; return plan
    }
    public func prepareCommit(draft: WorkspaceDraft, message: String, mergeParent: String? = nil) async throws -> MutationPlan {
        let lease = preparationEpoch
        guard bindings[draft.conversationID] == draft.scope, draftRevisions[draft.conversationID] == draft.revision, !draft.changes.isEmpty || mergeParent != nil,
              !message.isEmpty, message.count <= 1000 else { throw RMError.staleReview }
        guard !receipts.contains(where:{ $0.scope.repositoryID == draft.scope.repositoryID && [.uncertain,.executing].contains($0.state) }) else { throw RMError.uncertainWrite }
        _ = try await github.verify(draft.scope,permission:"push")
        guard try await github.head(draft.scope) == draft.baseSHA else { throw RMError.conflict }
        try Task.checkCancellation(); guard lease == preparationEpoch else { throw RMError.staleReview }
        var args: [String:JSON] = ["message":.string(message)]
        if let mergeParent { args["merge_parent"] = .string(try InputValidation.sha(mergeParent)) }
        let plan = MutationPlan(scope:draft.scope,conversationID:draft.conversationID,operation:"commit",arguments:.object(args),before:.null,
            expectedRemoteDigest:"",expectedHead:draft.baseSHA,draft:draft,
            risk:draft.changes.contains(where:{ $0.original != nil && $0.updated == nil }) ? .consequential : .mutation)
        try validate(plan.id, candidate:plan); plans[plan.id] = plan; return plan
    }
    public func cancel(_ id: UUID) { confirmations[id]?.cancel(); plans[id] = nil }
    /// Called only by native review UI. There is no serializable proof or remote approval route.
    public func confirm(_ id: UUID, typedRepositoryName: String? = nil) async throws -> MutationReceipt {
        guard confirmations[id] == nil else { throw RMError.staleReview }
        let task = Task { try await self.performConfirmation(id,typedRepositoryName:typedRepositoryName) }
        confirmations[id] = task
        defer { confirmations[id] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func performConfirmation(_ id:UUID,typedRepositoryName:String?) async throws -> MutationReceipt {
        guard let plan = plans[id], !consuming.contains(id) else { throw RMError.staleReview }
        try validate(id)
        guard !repositoryWrites.contains(plan.scope.repositoryID), !receipts.contains(where:{ $0.scope.repositoryID == plan.scope.repositoryID && ($0.state == .executing || $0.state == .uncertain) }) else { throw RMError.uncertainWrite }
        consuming.insert(id); repositoryWrites.insert(plan.scope.repositoryID)
        defer { consuming.remove(id); repositoryWrites.remove(plan.scope.repositoryID) }
        if plan.risk == .destructive {
            guard typedRepositoryName == plan.scope.fullName else { throw RMError.forbidden }
        }
        if plan.risk == .consequential || plan.risk == .destructive {
            guard try await authenticator.authenticate(action:plan.operation,target:plan.scope.fullName) else { throw RMError.authentication }
        }
        try validate(id)
        if plan.accountCreation == true {
            let snapshot = try await github.creationSnapshot(plan.scope)
            guard RecordCrypto.digest(snapshot.encoded) == plan.expectedRemoteDigest else { throw RMError.staleReview }
        } else {
            _ = try await github.verify(plan.scope,permission:plan.operation == "commit" ? "push" : ToolCatalog.named(plan.operation).permission)
            guard try await github.head(plan.scope) == plan.expectedHead else { throw RMError.conflict }
        }
        if plan.operation != "commit",plan.accountCreation != true {
            let snapshot = try await github.remoteSnapshot(ToolCatalog.named(plan.operation),arguments:plan.arguments,scope:plan.scope)
            guard RecordCrypto.digest(snapshot.encoded) == plan.expectedRemoteDigest else { throw RMError.staleReview }
        }
        try validate(id)
        var receipt = MutationReceipt(plan:plan,state:.executing)
        receipts.append(receipt); try await persist()
        do {
            let result: JSON
            if plan.accountCreation == true {
                result = try await github.createRepository(plan) { try await self.validate(id) }
            } else if plan.operation == "commit" {
                result = try await github.publish(plan,message:plan.arguments["message"].string ?? "Reviewed change") { try await self.validate(id) }
            } else {
                try validate(id)
                result = try await github.mutate(ToolCatalog.named(plan.operation),arguments:plan.arguments,scope:plan.scope) { try await self.validate(id) }
            }
            receipt.state = result["http_status"].int == 202 ? .accepted : .completed
            receipt.result = GitHubRedaction.clean(result); plans[id] = nil
        } catch {
            let e = error as? RMError ?? .uncertainWrite
            receipt.state = e == .uncertainWrite ? .uncertain : .failed
            receipt.result = .object(["error":.string(e.rawValue)])
            plans[id] = nil; replace(receipt); try await persist(); throw e
        }
        replace(receipt); try await persist(); return receipt
    }
    /// Refresh the reviewed target and keep uncertain status until the user confirms observed outcome.
    public func reconciliation(_ id: UUID) async throws -> JSON {
        guard let receipt = receipts.first(where:{ $0.id == id }), receipt.state == .uncertain else { throw RMError.invalidInput }
        return try await github.reconcile(receipt)
    }
    public func acknowledgeReconciliation(_ id: UUID, observedOutcome: String) async throws {
        guard let i = receipts.firstIndex(where:{ $0.id == id && $0.state == .uncertain }), !observedOutcome.isEmpty else { throw RMError.invalidInput }
        guard try await authenticator.authenticate(action:"Reconcile uncertain operation",target:receipts[i].scope.fullName) else { throw RMError.authentication }
        receipts[i].state = .failed; receipts[i].result = .object(["reconciled_by_user":.string(String(observedOutcome.prefix(1000)))])
        try await persist()
    }
    private func validate(_ id: UUID, candidate: MutationPlan? = nil) throws {
        guard let p = candidate ?? plans[id], p.expires > now(),
              bindings[p.conversationID] == (p.accountCreation == true ? p.initiatingScope : p.scope) else { throw RMError.staleReview }
        if let draft = p.draft, draftRevisions[p.conversationID] != draft.revision { throw RMError.staleReview }
        try Task.checkCancellation()
    }
    private func replace(_ receipt: MutationReceipt) { if let i = receipts.firstIndex(where:{ $0.id == receipt.id }) { receipts[i] = receipt } }
    private func persist() async throws { try await vault.save(receipts,id:"operation-journal") }
    private func validateBody(_ d: ToolDefinition, arguments: JSON) throws {
        if ["create_branch","create_tag"].contains(d.name) {
            guard let ref = arguments["body"]["ref"].string, ref.hasPrefix(d.name == "create_branch" ? "refs/heads/" : "refs/tags/") else { throw RMError.invalidInput }
            _ = try InputValidation.ref(String(ref.dropFirst(d.name == "create_branch" ? 11 : 10)))
            _ = try InputValidation.sha(arguments["body"]["sha"].string ?? "")
        }
        for key in ["base","head","default_branch","target_commitish","tag_name"] {
            if let value = arguments["body"][key].string { _ = try InputValidation.ref(value) }
        }
        if let url = arguments["body"]["config"]["url"].string { guard let url = URL(string:url) else { throw RMError.invalidInput }; try URLPolicy.validate(url) }
        if !d.nativeOnly, !RepositorySecretScanner.scan(arguments.pretty).findings.isEmpty { throw RMError.forbidden }
    }
}
