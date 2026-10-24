import Foundation

public enum ReasoningPreference: String, Codable, CaseIterable, Sendable {
    case automatic, off, minimal, low, medium, high, xhigh, max
    public var title: String {
        switch self {
        case .automatic: String(localized:"Auto",bundle:.module); case .off: String(localized:"Least reasoning",bundle:.module); case .minimal: String(localized:"Minimal",bundle:.module); case .low: String(localized:"Light",bundle:.module)
        case .medium: String(localized:"Balanced",bundle:.module); case .high: String(localized:"Deep",bundle:.module); case .xhigh: String(localized:"Extended",bundle:.module); case .max: String(localized:"Maximum",bundle:.module)
        }
    }
}

/// A wire contract, never inferred from words in a model's output.
public struct ReasoningCapabilities: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case providerDefault, promptGuidance, apple, openAI, anthropicAdaptive, anthropicBudget
        case geminiLevel, geminiBudget, deepSeek, openRouter, xAI, mistral
    }
    public var kind: Kind
    public var levels: [ReasoningPreference]
    public var canDisable: Bool
    public var nativeAdaptive: Bool
    public var minimumBudget: Int?
    public var maximumBudget: Int?
    public init(kind: Kind, levels: [ReasoningPreference] = [.low,.medium,.high], canDisable: Bool = false,
                nativeAdaptive: Bool = false, minimumBudget: Int? = nil, maximumBudget: Int? = nil) {
        self.kind = kind; self.levels = levels.filter { $0 != .automatic && $0 != .off }
        self.canDisable = canDisable; self.nativeAdaptive = nativeAdaptive
        self.minimumBudget = minimumBudget; self.maximumBudget = maximumBudget
    }
    public var choices: [ReasoningPreference] {
        [.automatic] + (canDisable ? [.off] : []) + levels
    }
}

public struct ReasoningDecision: Codable, Equatable, Sendable {
    public var requested: ReasoningPreference
    public var resolved: ReasoningPreference?
    public var kind: ReasoningCapabilities.Kind
    public var tokenBudget: Int?
    public var explanation: String
    public var label: String {
        let value = resolved?.title ?? String(localized:"Provider adaptive",bundle:.module)
        return requested == .automatic ? String(localized:"Auto · \(value)",bundle:.module) : value
    }
}

/// Encrypted with the conversation. Replay only to this exact profile and model.
public struct ProviderContinuation: Codable, Equatable, Sendable {
    public var profileID: UUID
    public var modelID: String
    public var endpoint: String?
    public var payload: JSON
    public init(profileID: UUID, modelID: String, endpoint:String? = nil,payload: JSON) {
        self.profileID = profileID; self.modelID = modelID; self.endpoint = endpoint; self.payload = payload
    }
    public func payload(for request: RunRequest) -> JSON? {
        profileID == request.profile.id && modelID == request.model && endpoint == request.profile.endpoint ? payload : nil
    }
}

public enum ReasoningPolicy {
    /// Conservative known contracts; catalog metadata or explicit configuration takes precedence.
    public static func capabilities(profile: ProviderProfile, model: String) -> ReasoningCapabilities {
        if let explicit = profile.models.first(where: { $0.id == model })?.reasoning { return explicit }
        let id = model.lowercased().replacingOccurrences(of:"models/",with:"")
        switch profile.preset {
        case .apple:
            return id == "apple-private-cloud" ? .init(kind:.apple) : .init(kind:.promptGuidance,canDisable:true)
        case .openCodeGo,.openCodeZen:
            var upstream = profile
            if id.hasPrefix("gpt-") || id.hasPrefix("o3") || id.hasPrefix("o4") { upstream.preset = .openAI }
            else if id.hasPrefix("claude-") { upstream.preset = .anthropic }
            else if id.hasPrefix("gemini-") { upstream.preset = .gemini }
            else if id.hasPrefix("grok-") { upstream.preset = .xAI }
            else if id.hasPrefix("deepseek-") { upstream.preset = .deepSeek }
            else if id.hasPrefix("magistral-") { upstream.preset = .mistral }
            else { return .init(kind:.providerDefault,levels:[],nativeAdaptive:true) }
            return capabilities(profile:upstream,model:model)
        case .openAI:
            if id.hasPrefix("gpt-6.1-sol") || id.hasPrefix("gpt-6-sol") || id.hasPrefix("gpt-6-luna") || id.hasPrefix("gpt-6-astra") {
                return .init(kind:.openAI,levels:[.low,.medium,.high,.xhigh,.max])
            }
            if id.hasPrefix("gpt-5.6") || id.hasPrefix("gpt-5.5") || id.hasPrefix("gpt-5.4") || id.hasPrefix("gpt-5.2") || id.hasPrefix("gpt-5.1") {
                return .init(kind:.openAI,levels:[.low,.medium,.high,.xhigh],canDisable:true)
            }
            if id.hasPrefix("gpt-5") || id.hasPrefix("o3") || id.hasPrefix("o4-mini") || id.hasPrefix("o1") { return .init(kind:.openAI) }
        case .anthropic:
            let adaptive = ["claude-opus-4-6","claude-opus-4-7","claude-opus-4-8","claude-sonnet-4-6","claude-opus-5","claude-sonnet-5","claude-haiku-5-5","claude-fable-5","claude-mythos-5"].contains { id.hasPrefix($0) }
            if adaptive {
                let xhigh = !id.hasPrefix("claude-opus-4-6") && !id.hasPrefix("claude-sonnet-4-6")
                let always = id.hasPrefix("claude-opus-5-5") || id.hasPrefix("claude-fable") || id.hasPrefix("claude-mythos")
                return .init(kind:.anthropicAdaptive,levels:[.low,.medium,.high]+(xhigh ? [.xhigh,.max] : [.max]),canDisable:!always,nativeAdaptive:true)
            }
            if ["claude-sonnet-4","claude-opus-4","claude-3-7-sonnet","claude-haiku-4-5"].contains(where:{ id.hasPrefix($0) }) {
                return .init(kind:.anthropicBudget,canDisable:true,minimumBudget:1024)
            }
        case .gemini:
            if id.hasPrefix("gemini-3") {
                let flash = id.contains("flash")
                return .init(kind:.geminiLevel,levels:flash ? [.low,.medium,.high] : [.low,.high])
            }
            if id.hasPrefix("gemini-2.5") {
                return .init(kind:.geminiBudget,canDisable:!id.contains("pro"),nativeAdaptive:true,
                             minimumBudget:id.contains("pro") ? 128 : id.contains("lite") ? 512 : 0,maximumBudget:id.contains("pro") ? 32768 : 24576)
            }
        case .deepSeek:
            if id.hasPrefix("deepseek-v4") || id == "deepseek-chat" || id == "deepseek-reasoner" || id == "deepseek-flash" {
                return .init(kind:.deepSeek,levels:id.hasPrefix("deepseek-v4") ? [.high,.max] : [.medium],canDisable:id != "deepseek-reasoner")
            }
        case .xAI:
            if ["grok-4.5","grok-4.6","grok-4.7"].contains(where:{ id.hasPrefix($0) }) {
                return .init(kind:.xAI,levels:id.hasPrefix("grok-4.5") ? [.low,.medium,.high] : [.low,.medium,.high,.xhigh])
            }
            if id.hasPrefix("grok-3-mini") { return .init(kind:.xAI,levels:[.low,.high]) }
        case .mistral:
            if id.hasPrefix("magistral") { return .init(kind:.mistral,levels:[.medium],canDisable:true) }
        default: break
        }
        return .init(kind:.promptGuidance,canDisable:true)
    }

    public static func resolve(_ request: RunRequest) -> ReasoningDecision {
        let requested = request.reasoningPreference ?? (request.thinking ? .high : .automatic)
        let caps = capabilities(profile:request.profile,model:request.model)
        let ownText = request.messages.last(where: { $0.role == .user })?.text ?? ""
        var chosen: ReasoningPreference = requested
        var explanation = String(localized:"Your selected reasoning level.",bundle:.module)
        if requested == .automatic {
            if caps.nativeAdaptive {
                return .init(requested:requested,resolved:nil,kind:caps.kind,tokenBudget:caps.kind == .geminiBudget ? -1 : nil,
                             explanation:request.profile.usesChatGPT ? String(localized:"The model allocates reasoning for this request using its provider defaults.",bundle:.module) : String(localized:"The model allocates reasoning for this request within your output cap.",bundle:.module))
            }
            let difficult = ["security","threat","race condition","deadlock","architecture","migration","conflict","debug","review","audit","prove","reconcile"]
            let simple = ["translate","rename","format","summarize","shorter","hello"]
            let text = ownText.lowercased()
            let failures = request.messages.suffix(3).filter { $0.role == .tool && ($0.text.contains("failed") || $0.text.contains("conflict")) }.count
            if difficult.contains(where:text.contains) || failures > 0 || ownText.utf8.count > 6000 {
                chosen = .high; explanation = String(localized:"Deeper reasoning for review, debugging, or a complex request.",bundle:.module)
            } else if request.latencySensitive || (ownText.count < 180 && request.tools.isEmpty) || simple.contains(where:text.hasPrefix) {
                chosen = .low; explanation = String(localized:"Light reasoning for a short or latency-sensitive request.",bundle:.module)
            } else { chosen = .medium; explanation = String(localized:"Balanced reasoning for this repository workflow.",bundle:.module) }
            if caps.kind == .promptGuidance || caps.kind == .providerDefault {
                return .init(requested:requested,resolved:nil,kind:.providerDefault,tokenBudget:nil,
                             explanation:String(localized:"Native reasoning controls are not confirmed for this model; its default applies.",bundle:.module))
            }
        }
        if chosen == .off && !caps.canDisable {
            chosen = caps.levels.first ?? .low; explanation = String(localized:"This model requires reasoning; using its lowest supported level.",bundle:.module)
        } else if chosen != .off && !caps.levels.contains(chosen) {
            let order: [ReasoningPreference] = [.minimal,.low,.medium,.high,.xhigh,.max]
            let desired = order.firstIndex(of:chosen) ?? 1
            chosen = caps.levels.min { abs((order.firstIndex(of:$0) ?? 1)-desired) < abs((order.firstIndex(of:$1) ?? 1)-desired) } ?? .medium
            explanation = String(localized:"Mapped to the nearest supported level for this model.",bundle:.module)
        }
        var budget: Int?
        if caps.kind == .anthropicBudget || caps.kind == .geminiBudget {
            if chosen == .off { budget = 0 }
            else {
                let target = chosen == .low ? 1024 : chosen == .medium ? 2048 : 8192
                let cap = min(caps.maximumBudget ?? 32768,max(0,request.outputBudget-1024))
                if cap < (caps.minimumBudget ?? 0) {
                    return .init(requested:requested,resolved:nil,kind:.providerDefault,tokenBudget:nil,
                                 explanation:String(localized:"The output cap cannot fit the model's minimum thinking budget; keeping the provider default.",bundle:.module))
                }
                budget = min(cap,max(caps.minimumBudget ?? 0,target))
            }
        }
        if caps.kind == .promptGuidance { explanation = String(localized:"Answer guidance only; this model has no confirmed native reasoning control.",bundle:.module) }
        return .init(requested:requested,resolved:chosen,kind:caps.kind,tokenBudget:budget,explanation:explanation)
    }

    public static func prepare(_ request: RunRequest) -> RunRequest {
        var result = request; result.reasoningDecision = resolve(request)
        if result.reasoningDecision?.kind == .promptGuidance, let level = result.reasoningDecision?.resolved, level != .off {
            result.messages.insert(ChatMessage(role:.system,text:level == .low ? "Give a direct, concise answer. Check facts before responding." : "Check assumptions, alternatives, and relevant evidence before answering. Give the result and a concise explanation; do not expose private internal reasoning."),at:0)
        }
        return result
    }

    public static func apply(_ decision: ReasoningDecision, to body: inout [String:JSON], format: WireFormat) {
        let level = decision.resolved
        let effort = level == .off ? "none" : level?.rawValue
        switch decision.kind {
        case .openAI, .xAI:
            if let effort {
                if format == .responses {
                    body["reasoning"] = .object(decision.kind == .openAI ? ["effort":.string(effort),"summary":"auto"] : ["effort":.string(effort)])
                } else { body["reasoning_effort"] = .string(effort) }
            }
        case .anthropicAdaptive:
            if level == .off { body["thinking"] = .object(["type":"disabled"]) }
            else { body["thinking"] = .object(["type":"adaptive"]); if let effort { body["output_config"] = .object(["effort":.string(effort)]) } }
        case .anthropicBudget:
            if let budget = decision.tokenBudget { body["thinking"] = budget == 0 ? .object(["type":"disabled"]) : .object(["type":"enabled","budget_tokens":.number(Double(budget))]) }
        case .geminiBudget, .geminiLevel:
            var config = body["generationConfig"]?.object ?? [:]
            var thinking: [String:JSON] = ["includeThoughts":true]
            if let budget = decision.tokenBudget { thinking["thinkingBudget"] = .number(Double(budget)) }
            if decision.kind == .geminiLevel, let effort { thinking["thinkingLevel"] = .string(effort) }
            config["thinkingConfig"] = .object(thinking); body["generationConfig"] = .object(config)
        case .deepSeek:
            body["thinking"] = .object(["type":level == .off ? "disabled" : "enabled"])
            if let effort, level == .high || level == .max { body["reasoning_effort"] = .string(effort) }
        case .openRouter:
            if level == .off { body["reasoning"] = .object(["enabled":false]) }
            else if let effort { body["reasoning"] = .object(["effort":.string(effort)]) }
        case .mistral:
            body["reasoning_effort"] = .string(level == .off ? "none" : "high")
        default: break
        }
    }
}
