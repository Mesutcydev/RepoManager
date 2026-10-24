import Foundation
import FoundationModels
import RepoManagerCore

/// All surfaces dispatch through this router; Apple uses the same run and approval services.
struct AppProviderClient: ProviderClient {
    let cloud: CloudProviderClient
    let chatGPT: ChatGPTProviderClient
    let access: ProviderAccessGate
    let apple = AppleProviderClient()
    init(secrets: any SecretStore, chatGPTConnections: ChatGPTConnectionStore, access: ProviderAccessGate) {
        self.access = access
        cloud = CloudProviderClient(secrets:secrets); chatGPT = ChatGPTProviderClient(connections:chatGPTConnections)
    }
    func stream(_ request: RunRequest) -> AsyncThrowingStream<ChatEvent,Error> {
        if request.profile.usesChatGPT {
            guard AppChatGPTConfiguration.enabled else { return AsyncThrowingStream { $0.finish(throwing:RMError.unavailable) } }
            return chatGPT.stream(request)
        }
        if request.profile.preset == .apple { return apple.stream(request) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await access.require(request.profile)
                    for try await event in cloud.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing:error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    func catalog(_ profile: ProviderProfile) async throws -> [ModelMetadata] {
        try await access.require(profile)
        if profile.usesChatGPT { guard AppChatGPTConfiguration.enabled else { throw RMError.unavailable }; return try await chatGPT.catalog(profile) }
        return profile.preset == .apple ? await apple.catalog() : try await cloud.catalog(profile)
    }
}

struct AppleProviderClient: ProviderClient {
    static let systemID = "apple-on-device"
    static let cloudID = "apple-private-cloud"
    func catalog() async -> [ModelMetadata] {
        var local = ModelMetadata(id:Self.systemID,contextTokens:4096)
        local.reasoning = .init(kind:.promptGuidance,canDisable:true)
        local.availability = SystemLanguageModel.default.isAvailable ? nil : String(localized:"Enable Apple Intelligence on a supported device; system assets must be ready.")
        #if RM_APPLE_PCC
        if #available(iOS 27,macOS 27,*) {
            if SystemLanguageModel.default.capabilities.contains(.reasoning) { local.reasoning = .init(kind:.apple) }
            local.contextTokens = SystemLanguageModel.default.contextSize
        }
        #endif
        var cloud = ModelMetadata(id:Self.cloudID)
        cloud.reasoning = .init(kind:.apple)
        cloud.availability = String(localized:"Private Cloud Compute requires OS 27 and a provisioning profile granting the capability to Repo Manager.")
        #if RM_APPLE_PCC
        if #available(iOS 27,macOS 27,*), AppleCapability.isProvisioned {
            let model = PrivateCloudComputeLanguageModel()
            if !model.isAvailable { cloud.availability = String(localized:"Private Cloud Compute is not ready on this device.") }
            else if model.quotaUsage.isLimitReached { cloud.availability = String(localized:"Apple's current usage limit has been reached.") }
            else { cloud.availability = nil }
            cloud.contextTokens = try? await model.contextSize
        }
        #endif
        return [local,cloud]
    }
    func stream(_ input: RunRequest) -> AsyncThrowingStream<ChatEvent,Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard input.profile.endpoint == ProviderPreset.apple.endpoint,
                          input.profile.consentEndpoint == input.profile.endpoint else { throw RMError.consentRequired }
                    var request = input.reasoningDecision == nil ? ReasoningPolicy.prepare(ContextBudget.prepare(input)) : input
                    if request.model == Self.cloudID {
                        #if RM_APPLE_PCC
                        if #available(iOS 27,macOS 27,*), AppleCapability.isProvisioned {
                            let model = PrivateCloudComputeLanguageModel()
                            guard model.isAvailable, !model.quotaUsage.isLimitReached else { throw RMError.unavailable }
                            try await Self.run(request,model:model,into:continuation)
                        } else { throw RMError.unavailable }
                        #else
                        throw RMError.unavailable
                        #endif
                    } else if request.model == Self.systemID {
                        let model = SystemLanguageModel.default
                        guard model.isAvailable else { throw RMError.unavailable }
                        let capture = AppleToolCapture()
                        let tools = try request.tools.map { try AppleToolHandoff(definition:$0,capture:capture) }
                        let transcript = try Self.transcript(request,tools:tools)
                        let session = LanguageModelSession(model:model,tools:tools,transcript:transcript.history)
                        let options = GenerationOptions(maximumResponseTokens:request.outputBudget)
                        #if RM_APPLE_PCC
                        if #available(iOS 27,macOS 27,*), model.capabilities.contains(.reasoning) {
                            request.reasoningDecision = ReasoningPolicy.resolve(request)
                            try await Self.collect(session.streamResponse(to:transcript.prompt,options:options,contextOptions:Self.context(request)),session:session,capture:capture,into:continuation)
                        } else {
                            try await Self.collect(session.streamResponse(to:transcript.prompt,options:options),session:session,capture:capture,into:continuation)
                        }
                        #else
                        try await Self.collect(session.streamResponse(to:transcript.prompt,options:options),session:session,capture:capture,into:continuation)
                        #endif
                    } else { throw RMError.invalidInput }
                    continuation.finish()
                } catch is CancellationError { continuation.finish(throwing:RMError.cancelled) }
                catch { continuation.finish(throwing:error as? RMError ?? .upstream) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #if RM_APPLE_PCC
    @available(iOS 27,macOS 27,*)
    private static func run(_ request:RunRequest,model:PrivateCloudComputeLanguageModel,into continuation:AsyncThrowingStream<ChatEvent,Error>.Continuation) async throws {
        let capture = AppleToolCapture()
        let tools = try request.tools.map { try AppleToolHandoff(definition:$0,capture:capture) }
        let transcript = try transcript(request,tools:tools)
        let size = try await model.contextSize
        let tokens = request.messages.reduce(0) { $0+ContextBudget.estimate($1) }+request.tools.reduce(0) { $0+ToolSelection.cost($1)+40 }
        guard tokens+request.outputBudget+128 <= size else { throw RMError.tooLarge }
        let session = LanguageModelSession(model:model,tools:tools,transcript:transcript.history)
        try await collect(session.streamResponse(to:transcript.prompt,options:GenerationOptions(maximumResponseTokens:request.outputBudget),contextOptions:context(request)),session:session,capture:capture,into:continuation)
    }
    @available(iOS 27,macOS 27,*)
    private static func context(_ request:RunRequest) -> ContextOptions {
        let level: ContextOptions.ReasoningLevel?
        switch request.reasoningDecision?.resolved {
        case .minimal,.low,.off: level = .light
        case .high,.xhigh,.max: level = .deep
        case .medium: level = .moderate
        default: level = nil
        }
        return ContextOptions(reasoningLevel:level)
    }
    #endif
    private static func collect(_ stream:LanguageModelSession.ResponseStream<String>,session:LanguageModelSession,capture:AppleToolCapture,into continuation:AsyncThrowingStream<ChatEvent,Error>.Continuation) async throws {
        var previous = ""
        do {
            for try await snapshot in stream {
                try Task.checkCancellation()
                let full = snapshot.content
                guard full.hasPrefix(previous), full.utf8.count <= 8*1024*1024 else { throw RMError.upstream }
                let delta = String(full.dropFirst(previous.count)); previous = full
                if !delta.isEmpty { continuation.yield(.text(delta)) }
            }
        } catch {
            try Task.checkCancellation()
            if await capture.calls().isEmpty { throw error }
        }
        try Task.checkCancellation()
        for call in await capture.calls() { continuation.yield(.tool(call)) }
        #if RM_APPLE_PCC
        if #available(iOS 27,macOS 27,*) {
            let usage = session.usage
            continuation.yield(.usage(Usage(input:usage.input.totalTokenCount,output:usage.output.totalTokenCount,reasoning:usage.output.reasoningTokenCount)))
        }
        #endif
        // Apple's private transcript reasoning is never exposed, persisted, or fabricated.
        continuation.yield(.finish(await capture.calls().isEmpty ? "stop" : "tool_calls"))
    }
    private static func transcript(_ request:RunRequest,tools:[AppleToolHandoff]) throws -> (history:Transcript,prompt:String) {
        let instructions = request.messages.filter { $0.role == .system }.map(\.text).joined(separator:"\n\n")
        var entries: [Transcript.Entry] = [.instructions(.init(segments:[.text(.init(content:instructions))],toolDefinitions:tools.map { .init(tool:$0) }))]
        let messages = request.messages.filter { $0.role != .system }
        var prompt = "Continue from the supplied tool results."
        for (index,message) in messages.enumerated() {
            let segments: [Transcript.Segment] = [.text(.init(content:message.text))]
            switch message.role {
            case .user:
                if index == messages.count-1 { prompt = message.text } else { entries.append(.prompt(.init(segments:segments))) }
            case .assistant:
                if !message.text.isEmpty { entries.append(.response(.init(assetIDs:[],segments:segments))) }
                if !message.calls.isEmpty {
                    entries.append(.toolCalls(.init(try message.calls.map { .init(id:$0.id,toolName:$0.name,arguments:try GeneratedContent(json:$0.arguments.pretty)) })))
                }
            case .tool:
                guard let id = message.toolCallID, let name = message.calls.first?.name else { throw RMError.invalidInput }
                entries.append(.toolOutput(.init(id:id,toolName:name,segments:segments)))
            default: break
            }
        }
        return (Transcript(entries:entries),prompt)
    }
}

private actor AppleToolCapture {
    private var pending: [ToolCall] = []
    func record(_ call:ToolCall) throws { guard pending.count < 25 else { throw RMError.tooLarge }; pending.append(call) }
    func calls() -> [ToolCall] { pending }
}
private struct AppleToolHandoff: FoundationModels.Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String
    let definition: RepoManagerCore.ToolDefinition
    let capture: AppleToolCapture
    let parameters: GenerationSchema
    var name:String { definition.name }
    var description:String { definition.description }
    init(definition:RepoManagerCore.ToolDefinition,capture:AppleToolCapture) throws {
        self.definition = definition; self.capture = capture
        parameters = try GenerationSchema(root:Self.schema(definition.schema,name:definition.name+"Arguments"),dependencies:[])
    }
    func call(arguments:GeneratedContent) async throws -> String {
        try Task.checkCancellation()
        let value = try JSON.parse(Data(arguments.jsonString.utf8))
        try Schema.validate(value,against:definition.schema)
        try await capture.record(ToolCall(name:definition.name,arguments:value))
        // Foundation Models stops here. Only RunCoordinator can execute app tools.
        throw Handoff.requested
    }
    private enum Handoff: Error { case requested }
    private static func schema(_ json:JSON,name:String) throws -> DynamicGenerationSchema {
        if let choices = json["enum"].array?.compactMap(\.string), !choices.isEmpty { return .init(name:name,anyOf:choices) }
        switch json["type"].string {
        case "object":
            let required = Set((json["required"].array ?? []).compactMap(\.string))
            let properties = try (json["properties"].object ?? [:]).sorted { $0.key < $1.key }.map { key,value in
                DynamicGenerationSchema.Property(name:key,description:value["description"].string,schema:try schema(value,name:name+key.capitalized),isOptional:!required.contains(key))
            }
            return .init(name:name,properties:properties)
        case "array": return .init(arrayOf:try schema(json["items"],name:name+"Item"),maximumElements:json["maxItems"].int ?? 100)
        case "integer": return .init(type:Int.self)
        case "number": return .init(type:Double.self)
        case "boolean": return .init(type:Bool.self)
        case "string": return .init(type:String.self)
        default: throw RMError.invalidInput
        }
    }
}
