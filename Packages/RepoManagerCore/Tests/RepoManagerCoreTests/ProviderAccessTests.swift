import Testing
import Foundation
@testable import RepoManagerCore

@Suite struct ProviderAccessTests {
    @Test func sameOpenAIEndpointDistinguishesChatGPTFromAPIKey() async throws {
        let gate = ProviderAccessGate(enforced:true)
        var chatGPT = ProviderProfile(preset:.openAI); chatGPT.authentication = .chatGPT
        try await gate.require(chatGPT)
        let api = ProviderProfile(preset:.openAI)
        #expect(chatGPT.endpoint == api.endpoint)
        await #expect(throws:RMError.proRequired) { try await gate.require(api) }
    }
    @Test func includedProvidersDoNotDependOnProPurchase() async throws {
        let gate = ProviderAccessGate(enforced:true)
        var chatGPT = ProviderProfile(preset:.openAI); chatGPT.authentication = .chatGPT
        for _ in 0..<2 {
            try await gate.require(ProviderProfile(preset:.apple))
            try await gate.require(chatGPT)
            await gate.setUnlocked(true)
        }
        await gate.setUnlocked(false)
        try await gate.require(chatGPT)
        try await gate.require(ProviderProfile(preset:.apple))
    }
    @Test func everyHostedAndCustomPresetRequiresPro() async throws {
        let gate = ProviderAccessGate(enforced:true)
        for preset in ProviderPreset.allCases where preset != .apple {
            await #expect(throws:RMError.proRequired) { try await gate.require(ProviderProfile(preset:preset)) }
        }
    }
    @Test func restoreAndRevocationChangeOnlyAPIAccess() async throws {
        let gate = ProviderAccessGate(enforced:true)
        let profile = ProviderProfile(preset:.custom)
        await #expect(throws:RMError.proRequired) { try await gate.require(profile) }
        await gate.setUnlocked(true); try await gate.require(profile)
        await gate.setUnlocked(false)
        await #expect(throws:RMError.proRequired) { try await gate.require(profile) }
        try await gate.require(ProviderProfile(preset:.apple))
    }
    @Test func disabledPaidRolloutPreservesCurrentFreeBuild() async throws {
        let gate = ProviderAccessGate(enforced:false)
        for preset in ProviderPreset.allCases { try await gate.require(ProviderProfile(preset:preset)) }
    }
    @Test func deniedInferenceNeverInvokesUnderlyingProvider() async throws {
        let calls = AccessCallCounter(),gate = ProviderAccessGate(enforced:true)
        let client = GatedProviderClient(base:AccessCountingProvider(calls:calls),access:gate)
        let api = ProviderProfile(preset:.openAI)
        let request = RunRequest(conversationID:UUID(),profile:api,model:"fixture",messages:[])
        await #expect(throws:RMError.proRequired) { for try await _ in client.stream(request) {} }
        #expect(await calls.count() == 0)
        await gate.setUnlocked(true)
        for try await _ in client.stream(request) {}
        #expect(await calls.count() == 1)
        await gate.setUnlocked(false)
        await #expect(throws:RMError.proRequired) { for try await _ in client.stream(request) {} }
        #expect(await calls.count() == 1)
    }
}
private actor AccessCallCounter {
    var value = 0
    func record() { value += 1 }
    func count() -> Int { value }
}
private struct AccessCountingProvider: ProviderClient {
    let calls: AccessCallCounter
    func stream(_ request: RunRequest) -> AsyncThrowingStream<ChatEvent,Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await calls.record(); continuation.finish() }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
