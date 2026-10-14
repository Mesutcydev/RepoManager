import Foundation
import Testing
@testable import RepoManagerCore

@Suite struct ReasoningTests {
    func request(_ preset:ProviderPreset,_ model:String,_ preference:ReasoningPreference = .automatic,_ text:String = "Review the repository security and find race conditions.") -> RunRequest {
        var r = RunRequest(conversationID:UUID(),profile:ProviderProfile(preset:preset),model:model,messages:[ChatMessage(role:.user,text:text)])
        r.reasoningPreference = preference; return r
    }
    @Test func appleAdaptsWithoutIncreasingBudget() {
        var r = request(.apple,"apple-private-cloud")
        #expect(ReasoningPolicy.resolve(r).resolved == .high)
        r.messages = [ChatMessage(role:.user,text:"Hello")]; r.latencySensitive = true
        #expect(ReasoningPolicy.resolve(r).resolved == .low)
        #expect(ReasoningPolicy.prepare(r).outputBudget == 4096)
        r.reasoningPreference = .off
        #expect(ReasoningPolicy.resolve(r).resolved == .low)
    }
    @Test func nativeAdaptiveAndBudgetCaps() throws {
        let claude = try ProviderWire.body(request(.anthropic,"claude-opus-4-6"))
        #expect(claude["thinking"]["type"].string == "adaptive")
        #expect(claude["output_config"] == .null)
        let gemini = try ProviderWire.body(request(.gemini,"gemini-2.5-flash"))
        #expect(gemini["generationConfig"]["thinkingConfig"]["thinkingBudget"].int == -1)
        let oldClaude = try ProviderWire.body(request(.anthropic,"claude-sonnet-4-5",.high))
        #expect(oldClaude["thinking"]["budget_tokens"].int == 3072)
        #expect(oldClaude["max_tokens"].int == 4096)
        let compulsory = ReasoningPolicy.resolve(request(.gemini,"gemini-2.5-pro",.off))
        #expect(compulsory.resolved == .low)
    }
    @Test func unsupportedModelHasHonestGuidance() throws {
        let r = request(.custom,"unlisted-model")
        #expect(ReasoningPolicy.resolve(r).kind == .providerDefault)
        #expect(try ProviderWire.body(r)["reasoning"] == .null)
        let manual = ReasoningPolicy.prepare(request(.custom,"unlisted-model",.high))
        #expect(manual.reasoningDecision?.kind == .promptGuidance)
        #expect(manual.messages.first?.role == .system)
    }
    @Test(arguments:[("gpt-6-luna",WireFormat.responses),("claude-haiku-5-5",.anthropic),("gemini-3-flash",.gemini),("minimax-m3",.anthropic),("qwen3.8-max",.anthropic),("deepseek-v4-pro",.chatCompletions)])
    func openCodeModelSpecificRoutes(_ id:String,_ format:WireFormat) throws {
        for preset in [ProviderPreset.openCodeGo,.openCodeZen] {
            var r = request(preset,id); r.profile.consentEndpoint = r.profile.endpoint
            #expect(ProviderRouting.format(profile:r.profile,model:id) == format)
            let http = try ProviderWire.request(r,key:"fixture")
            #expect(http.value(forHTTPHeaderField:"User-Agent") == "RepoManager/1.0")
            #expect(http.value(forHTTPHeaderField:"x-opencode-session") == r.conversationID.uuidString)
            #expect(http.url?.host == "opencode.ai")
            if id == "gpt-6-luna" { #expect(try JSON.parse(http.httpBody!)["reasoning"]["effort"].string == "high") }
        }
    }
    @Test func openRouterCatalogHonorsMandatoryAndExactLevels() throws {
        let p = ProviderProfile(preset:.openRouter)
        let row:JSON = .object(["id":"vendor/reasoner","reasoning":.object(["supported_efforts":.array(["high","low"]),"mandatory":true]),"pricing":.object(["prompt":"0.000001","completion":"0.000002"])])
        let m = try #require(try ProviderRouting.metadata(row,profile:p))
        #expect(m.reasoning?.choices == [.automatic,.high,.low]); #expect(m.inputCostPerMillion == 1)
        var r = request(.openRouter,m.id,.medium); r.profile.models = [m]
        #expect(ReasoningPolicy.resolve(r).resolved == .high || ReasoningPolicy.resolve(r).resolved == .low)
        #expect(try ProviderWire.body(r)["reasoning"]["effort"] != .null)
        let router = try #require(try ProviderRouting.metadata(.object(["id":"openrouter/auto"]),profile:p))
        #expect(router.reasoning?.choices == [.automatic])
    }
    @Test func signedThinkingReplayStaysInItsProfile() throws {
        var decoder = ProviderEventDecoder(format:.anthropic)
        let frames:[JSON] = [.object(["type":"content_block_start","index":0,"content_block":.object(["type":"thinking","thinking":""])]),
                             .object(["type":"content_block_delta","index":0,"delta":.object(["thinking":"summary"])]),
                             .object(["type":"content_block_delta","index":0,"delta":.object(["signature":"opaque-signature"])]),.object(["type":"message_stop"])]
        var state:JSON?
        for frame in frames { for event in try decoder.decode(SSEFrame(event:"message",data:frame.encoded)) { if case .providerState(let value) = event { state = value } } }
        var r = request(.anthropic,"claude-opus-4-6")
        var answer = ChatMessage(role:.assistant,text:"Answer")
        answer.providerContinuation = ProviderContinuation(profileID:r.profile.id,modelID:r.model,endpoint:r.profile.endpoint,payload:try #require(state))
        r.messages.append(answer)
        #expect(try ProviderWire.body(r)["messages"].array?.last?["content"].array?.first?["signature"].string == "opaque-signature")
        r.profile.id = UUID()
        #expect(try ProviderWire.body(r)["messages"].array?.last?["content"].array?.first?["signature"] == .null)
    }
    @Test func openRouterEncryptedDetailsSurviveFragmentation() throws {
        var decoder = ProviderEventDecoder(format:.chatCompletions)
        var events:[ChatEvent] = []
        for text in ["first-","second"] {
            let row:JSON = .object(["choices":.array([.object(["delta":.object(["reasoning_details":.array([.object(["id":"r1","index":0,"type":"reasoning.encrypted","data":.string(text)])])])])])])
            events += try decoder.decode(SSEFrame(event:"message",data:row.encoded))
        }
        events += try decoder.decode(SSEFrame(event:"message",data:JSON.object(["choices":.array([.object(["delta":.object([:]),"finish_reason":"tool_calls"])])]).encoded))
        let state = try #require(events.compactMap { event -> JSON? in if case .providerState(let value) = event { value } else { nil } }.last)
        #expect(state["reasoning_details"].array?.first?["data"].string == "first-second")
        #expect(!events.contains { if case .reasoning = $0 { true } else { false } })
    }
}
