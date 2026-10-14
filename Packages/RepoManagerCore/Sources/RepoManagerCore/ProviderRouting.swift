import Foundation

public enum ProviderRouting {
    public static func format(profile:ProviderProfile,model:String) -> WireFormat {
        if profile.usesChatGPT { return .responses }
        if let configured = profile.models.first(where:{ $0.id == model })?.format { return configured }
        guard profile.preset == .openCodeGo || profile.preset == .openCodeZen else { return profile.format }
        let id = model.lowercased()
        if id.hasPrefix("claude-") || id.hasPrefix("minimax-") || id.hasPrefix("qwen3.7-") || id.hasPrefix("qwen3.8-") { return .anthropic }
        if id.hasPrefix("gpt-") || id.hasPrefix("grok-") || id.hasPrefix("muse-spark-") { return .responses }
        if id.hasPrefix("gemini-") { return .gemini }
        return .chatCompletions
    }
    public static func prepare(_ input:RunRequest) -> RunRequest {
        var request = input; request.profile.format = format(profile:input.profile,model:input.model); return request
    }
    public static func metadata(_ row:JSON,profile:ProviderProfile) throws -> ModelMetadata? {
        guard let id = row["id"].string ?? row["name"].string else { return nil }
        _ = try InputValidation.model(id)
        var result = ModelMetadata(id:id,contextTokens:row["context_length"].int ?? row["inputTokenLimit"].int ?? row["limit"]["context"].int,
                                 outputTokens:row["outputTokenLimit"].int ?? row["limit"]["output"].int ?? row["top_provider"]["max_completion_tokens"].int)
        if profile.preset == .openRouter || profile.preset == .openRouterFree {
            if let config = row["reasoning"].object {
                var levels: [ReasoningPreference] = []
                if config["supported_efforts"] == .null { levels = [.low,.medium,.high,.xhigh,.max] }
                else { levels = (config["supported_efforts"]?.array ?? []).compactMap { ReasoningPreference(rawValue:$0.string ?? "") } }
                result.reasoning = .init(kind:.openRouter,levels:levels,canDisable:config["mandatory"]?.bool != true,
                                         nativeAdaptive:levels.isEmpty)
            } else if row["reasoning"] == .null {
                // Router models must keep the gateway default; a general parameter list is not a per-model contract.
                result.reasoning = .init(kind:.providerDefault,levels:[],nativeAdaptive:true)
            }
            if let value = row["pricing"]["prompt"].string.flatMap(Double.init), value >= 0 { result.inputCostPerMillion = value*1_000_000 }
            if let value = row["pricing"]["completion"].string.flatMap(Double.init), value >= 0 { result.outputCostPerMillion = value*1_000_000 }
        }
        if profile.preset == .openCodeGo || profile.preset == .openCodeZen {
            result.format = format(profile:profile,model:id)
            if let supplied = row["reasoning"].object, let levels = supplied["supported_efforts"]?.array {
                // A protocol alone does not determine the model's reasoning wire format.
                var base = profile; base.models.removeAll { $0.id == id }
                let known = ReasoningPolicy.capabilities(profile:base,model:id)
                if known.kind != .providerDefault,known.kind != .promptGuidance {
                    result.reasoning = .init(kind:known.kind,levels:levels.compactMap { ReasoningPreference(rawValue:$0.string ?? "") },
                        canDisable:supplied["mandatory"]?.bool != true,nativeAdaptive:known.nativeAdaptive,
                        minimumBudget:known.minimumBudget,maximumBudget:known.maximumBudget)
                }
            }
        }
        return result
    }
}
