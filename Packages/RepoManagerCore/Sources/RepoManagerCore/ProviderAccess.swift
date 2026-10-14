import Foundation

/// App licensing is independent of destination consent and provider authentication.
public enum ProviderAccessPolicy {
    public static func requiresPro(_ profile: ProviderProfile) -> Bool {
        !profile.usesChatGPT && profile.preset != .apple
    }
}

/// Shared by app chat, comparison and the local agent's provider router.
public actor ProviderAccessGate {
    public let enforced: Bool
    private var unlocked = false
    public init(enforced: Bool) { self.enforced = enforced }
    public func setUnlocked(_ value: Bool) { unlocked = value }
    public func require(_ profile: ProviderProfile) throws {
        try Task.checkCancellation()
        if enforced && ProviderAccessPolicy.requiresPro(profile) && !unlocked { throw RMError.proRequired }
    }
}

/// Admission occurs before the wrapped client can inspect credentials or send a request.
public struct GatedProviderClient: ProviderClient {
    let base: any ProviderClient
    let access: ProviderAccessGate
    public init(base: any ProviderClient, access: ProviderAccessGate) { self.base = base; self.access = access }
    public func stream(_ request: RunRequest) -> AsyncThrowingStream<ChatEvent,Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await access.require(request.profile)
                    for try await event in base.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing:error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
