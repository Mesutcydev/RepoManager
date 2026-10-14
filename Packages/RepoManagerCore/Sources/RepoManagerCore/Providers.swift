import Foundation

public protocol ProviderClient: Sendable {
    func stream(_ request: RunRequest) -> AsyncThrowingStream<ChatEvent, Error>
}
public struct SSEFrame: Equatable, Sendable { public var event: String; public var data: Data }
/// Byte framing precedes UTF-8 decoding; a split multibyte scalar cannot be dropped.
public struct SSEParser: Sendable {
    private var bytes = Data()
    public init() {}
    public mutating func feed(_ data: Data, final: Bool = false) throws -> [SSEFrame] {
        bytes.append(data); guard bytes.count <= 1024 * 1024 else { throw RMError.tooLarge }
        var output: [SSEFrame] = []
        while let range = delimiter() {
            let raw = bytes.subdata(in: 0..<range.lowerBound); bytes.removeSubrange(0..<range.upperBound)
            if let frame = try parse(raw) { output.append(frame) }
        }
        if final && !bytes.isEmpty { if let frame = try parse(bytes) { output.append(frame) }; bytes.removeAll() }
        return output
    }
    private func delimiter() -> Range<Int>? {
        let a = bytes.range(of: Data([10,10])); let b = bytes.range(of: Data([13,10,13,10]))
        if let a, let b { return a.lowerBound < b.lowerBound ? a : b }; return a ?? b
    }
    private func parse(_ data: Data) throws -> SSEFrame? {
        guard let text = String(data: data, encoding: .utf8) else { throw RMError.invalidInput }
        var event = "message"; var fields: [String] = []
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("event:") { event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("data:") { fields.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }
        return fields.isEmpty ? nil : SSEFrame(event: event, data: Data(fields.joined(separator: "\n").utf8))
    }
}
public struct ProviderEventDecoder: Sendable {
    private struct Partial: Sendable { var id = ""; var name = ""; var arguments = "" }
    private var partials: [String: Partial] = [:]
    private var emitted = Set<String>()
    private var ready = Set<String>()
    private var geminiCalls: [ToolCall] = []
    private var thinkingBlocks: [Int:[String:JSON]] = [:]
    private var signedParts: [JSON] = []
    private var reasoningDetails: [String:[String:JSON]] = [:]
    private var responseReasoning: [JSON] = []
    public private(set) var completed = false
    public var format: WireFormat
    public init(format: WireFormat) { self.format = format }
    public mutating func decode(_ frame: SSEFrame) throws -> [ChatEvent] {
        if frame.data == Data("[DONE]".utf8) { completed = true; return [] }
        let root = try JSON.parse(frame.data)
        if root["error"] != .null || frame.event == "error" { throw RMError.upstream }
        var events: [ChatEvent] = []
        switch format {
        case .chatCompletions:
            if let u = root["usage"].object { events.append(.usage(Usage(input:u["prompt_tokens"]?.int,output:u["completion_tokens"]?.int,reasoning:u["completion_tokens_details"]?["reasoning_tokens"].int))) }
            for choice in root["choices"].array ?? [] {
                let delta = choice["delta"]
                if let t = delta["content"].string { events.append(.text(t)) }
                for chunk in delta["content"].array ?? [] {
                    if chunk["type"].string == "text",let text = chunk["text"].string { events.append(.text(text)) }
                    if chunk["type"].string == "thinking" {
                        for item in chunk["thinking"].array ?? [] { if let text = item["text"].string { events.append(.reasoning(text)) } }
                    }
                }
                if let t = delta["reasoning_content"].string ?? delta["reasoning"].string { events.append(.reasoning(t)) }
                for item in delta["reasoning_details"].array ?? [] {
                    let key = item["id"].string ?? String(item["index"].int ?? 0)
                    var combined = reasoningDetails[key] ?? [:]
                    for (field,value) in item.object ?? [:] {
                        if ["text","summary","data","signature"].contains(field), let next = value.string {
                            combined[field] = .string((combined[field]?.string ?? "")+next)
                        } else { combined[field] = value }
                    }
                    reasoningDetails[key] = combined
                    if delta["reasoning"].string == nil && delta["reasoning_content"].string == nil,
                       let summary = item["summary"].string ?? item["text"].string { events.append(.reasoning(summary)) }
                }
                for call in delta["tool_calls"].array ?? [] {
                    let index = String(call["index"].int ?? 0); var p = partials[index] ?? Partial()
                    if let id = call["id"].string { p.id = id }; if let name = call["function"]["name"].string { p.name += name }
                    p.arguments += call["function"]["arguments"].string ?? ""; partials[index] = p
                }
                if let reason = choice["finish_reason"].string {
                    completed = true
                    if reason == "tool_calls" { ready.formUnion(partials.keys); events += try finishTools() }
                    if !reasoningDetails.isEmpty { events.append(.providerState(.object(["reasoning_details":.array(reasoningDetails.keys.sorted().compactMap { reasoningDetails[$0].map(JSON.object) })]))) }
                    events.append(.finish(reason))
                }
            }
        case .responses:
            let type = root["type"].string ?? frame.event
            switch type {
            case "response.output_text.delta": if let t = root["delta"].string { events.append(.text(t)) }
            case "response.reasoning_summary_text.delta": if let t = root["delta"].string { events.append(.reasoning(t)) }
            case "response.output_item.added":
                let item = root["item"]; if item["type"].string == "function_call" {
                    partials[item["id"].string ?? ""] = Partial(id: item["call_id"].string ?? "", name: item["name"].string ?? "", arguments: item["arguments"].string ?? "")
                }
            case "response.function_call_arguments.delta":
                let id = root["item_id"].string ?? ""; var p = partials[id] ?? Partial(); p.arguments += root["delta"].string ?? ""; partials[id] = p
            case "response.output_item.done":
                if root["item"]["type"].string == "reasoning", root["item"]["encrypted_content"].string != nil { responseReasoning.append(root["item"]) }
                let item = root["item"]; if item["type"].string == "function_call" {
                    partials[item["id"].string ?? ""] = Partial(id: item["call_id"].string ?? "", name: item["name"].string ?? "", arguments: item["arguments"].string ?? "")
                    ready.insert(item["id"].string ?? "")
                }
            case "response.completed", "response.incomplete":
                let usage = root["response"]["usage"]
                events.append(.usage(Usage(input:usage["input_tokens"].int,output:usage["output_tokens"].int,reasoning:usage["output_tokens_details"]["reasoning_tokens"].int)))
                completed = true
                if type == "response.completed" { events += try finishTools() }
                if !responseReasoning.isEmpty { events.append(.providerState(.object(["responses":.array(responseReasoning)]))) }
                events.append(.finish(type == "response.completed" ? "stop" : "length"))
            case "response.failed": throw RMError.upstream
            default: break
            }
        case .anthropic:
            switch root["type"].string ?? frame.event {
            case "message_start":
                let u = root["message"]["usage"]; events.append(.usage(Usage(input: u["input_tokens"].int, output: u["output_tokens"].int)))
            case "content_block_start":
                let b = root["content_block"]; let index = root["index"].int ?? 0
                if b["type"].string == "tool_use" { partials[String(index)] = Partial(id:b["id"].string ?? "",name:b["name"].string ?? "",arguments:"") }
                if b["type"].string == "thinking" || b["type"].string == "redacted_thinking" { thinkingBlocks[index] = b.object }
            case "content_block_delta":
                let d = root["delta"]
                if let t = d["text"].string { events.append(.text(t)) }
                if let t = d["thinking"].string { events.append(.reasoning(t)) }
                let index = root["index"].int ?? 0
                if var block = thinkingBlocks[index] {
                    if let text = d["thinking"].string { block["thinking"] = .string((block["thinking"]?.string ?? "")+text) }
                    if let signature = d["signature"].string { block["signature"] = .string((block["signature"]?.string ?? "")+signature) }
                    thinkingBlocks[index] = block
                }
                if let args = d["partial_json"].string { let key = String(root["index"].int ?? 0); var p = partials[key] ?? Partial(); p.arguments += args; partials[key] = p }
            case "content_block_stop": ready.insert(String(root["index"].int ?? 0))
            case "message_delta":
                events.append(.usage(Usage(output: root["usage"]["output_tokens"].int)))
                if let reason = root["delta"]["stop_reason"].string {
                    if reason == "tool_use" { events += try finishTools() }
                    events.append(.finish(reason))
                }
            case "message_stop":
                let blocks = thinkingBlocks.keys.sorted().compactMap { key -> JSON? in
                    guard let block = thinkingBlocks[key], block["signature"]?.string != nil || block["type"]?.string == "redacted_thinking" else { return nil }
                    return .object(block)
                }
                if !blocks.isEmpty { events.append(.providerState(.object(["anthropic":.array(blocks)]))) }; completed = true
            default: break
            }
        case .gemini:
            let usage = root["usageMetadata"]
            if usage != .null { events.append(.usage(Usage(input:usage["promptTokenCount"].int,output:usage["candidatesTokenCount"].int,reasoning:usage["thoughtsTokenCount"].int))) }
            for candidate in root["candidates"].array ?? [] {
                for part in candidate["content"]["parts"].array ?? [] {
                    if part["thoughtSignature"].string != nil || part["functionCall"].object != nil { signedParts.append(part) }
                    if let t = part["text"].string { events.append(part["thought"].bool == true ? .reasoning(t) : .text(t)) }
                    if let name = part["functionCall"]["name"].string {
                        let args = part["functionCall"]["args"]; guard args.object != nil else { throw RMError.invalidInput }
                        geminiCalls.append(ToolCall(name: name, arguments: args))
                    }
                }
                if let reason = candidate["finishReason"].string {
                    completed = true
                    if reason == "STOP" { events += geminiCalls.map(ChatEvent.tool) }
                    if !signedParts.isEmpty { events.append(.providerState(.object(["gemini":.array(signedParts)]))) }
                    geminiCalls.removeAll(); events.append(.finish(reason == "MAX_TOKENS" ? "length" : reason.lowercased()))
                }
            }
        }
        for p in partials.values { guard p.arguments.utf8.count <= 1024 * 1024 else { throw RMError.tooLarge } }
        return events
    }
    private mutating func finishTools() throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for key in partials.keys.sorted() {
            guard ready.contains(key), let p = partials[key], !emitted.contains(key), !p.name.isEmpty else { continue }
            let args = p.arguments.isEmpty ? JSON.object([:]) : try JSON.parse(Data(p.arguments.utf8))
            guard args.object != nil, p.name.count <= 100 else { throw RMError.invalidInput }
            events.append(.tool(ToolCall(id: p.id.isEmpty ? UUID().uuidString : p.id, name: p.name, arguments: args))); emitted.insert(key)
        }
        return events
    }
}

public enum ProviderWire {
    public static func body(_ r: RunRequest) throws -> JSON {
        let routed = ProviderRouting.prepare(r)
        let r = routed.reasoningDecision == nil ? ReasoningPolicy.prepare(routed) : routed
        _ = try InputValidation.model(r.model)
        guard r.outputBudget > 0, r.outputBudget <= 131072 else { throw RMError.invalidInput }
        let system = r.messages.filter { $0.role == .system }.map(\.text).joined(separator: "\n\n")
        let messages = r.messages.filter { $0.role != .system }
        switch r.profile.format {
        case .responses:
            let input = messages.flatMap { m -> [JSON] in
                if m.role == .tool { return [.object(["type": "function_call_output", "call_id": .string(m.toolCallID ?? ""), "output": .string(m.text)])] }
                var rows: [JSON] = m.providerContinuation?.payload(for:r)?["responses"].array ?? []
                if !m.text.isEmpty { rows.append(.object(["role": .string(m.role.rawValue), "content": .string(m.text)])) }
                rows += m.calls.map { .object(["type": "function_call", "call_id": .string($0.id), "name": .string($0.name), "arguments": .string($0.arguments.pretty)]) }
                return rows
            }
            var b: [String: JSON] = ["model": .string(r.model), "input": .array(input), "instructions": .string(system), "stream": true, "store": false, "max_output_tokens": .number(Double(r.outputBudget))]
            if r.reasoningDecision?.kind == .openAI || r.reasoningDecision?.kind == .xAI { b["include"] = .array(["reasoning.encrypted_content"]) }
            if !r.tools.isEmpty { b["tools"] = .array(r.tools.map { .object(["type": "function", "name": .string($0.name), "description": .string($0.description), "parameters": $0.schema]) }) }
            if let decision = r.reasoningDecision { ReasoningPolicy.apply(decision,to:&b,format:r.profile.format) }
            if r.profile.usesChatGPT {
                try ChatGPTAuth.validateProfile(r.profile)
                // The SIWC preview forbids max_output_tokens and requires local
                // function tools in a namespace. Execution still uses native review.
                b["max_output_tokens"] = nil
                if let functions = b["tools"] {
                    b["tools"] = .array([.object(["type": "namespace", "name": "repo_manager",
                        "description": "Repo Manager tools. Remote mutations require native user review.", "tools": functions])])
                }
                b["input"] = .array(input.map { item in
                    guard item["type"].string == "function_call", var fields = item.object else { return item }
                    fields["namespace"] = "repo_manager"; return .object(fields)
                })
            }
            return .object(b)
        case .chatCompletions:
            var b: [String: JSON] = ["model": .string(r.model), "stream": true, "stream_options": .object(["include_usage": true]), "max_tokens": .number(Double(r.outputBudget))]
            b["messages"] = .array(r.messages.map { m in
                var x: [String: JSON] = ["role": .string(m.role.rawValue), "content": .string(m.text)]
                if r.profile.preset == .mistral,m.role == .assistant,!m.reasoning.isEmpty {
                    var chunks:[JSON] = [.object(["type":"thinking","thinking":.array([.object(["type":"text","text":.string(m.reasoning)])])])]
                    if !m.text.isEmpty { chunks.append(.object(["type":"text","text":.string(m.text)])) }
                    x["content"] = .array(chunks)
                }
                if (r.profile.preset == .deepSeek || r.profile.preset == .openCodeGo || r.profile.preset == .openCodeZen),m.role == .assistant,
                   !m.reasoning.isEmpty,m.providerContinuation?.payload(for:r) != nil { x["reasoning_content"] = .string(m.reasoning) }
                if r.profile.preset == .openRouter || r.profile.preset == .openRouterFree, m.role == .assistant {
                    if let details = m.providerContinuation?.payload(for:r)?["reasoning_details"].array { x["reasoning_details"] = .array(details) }
                    else if !m.reasoning.isEmpty { x["reasoning"] = .string(m.reasoning) }
                }
                if let id = m.toolCallID { x["tool_call_id"] = .string(id) }
                if !m.calls.isEmpty { x["tool_calls"] = .array(m.calls.map { .object(["id": .string($0.id), "type": "function", "function": .object(["name": .string($0.name), "arguments": .string($0.arguments.pretty)])]) }) }
                return .object(x)
            })
            if !r.tools.isEmpty { b["tools"] = .array(r.tools.map { .object(["type": "function", "function": .object(["name": .string($0.name), "description": .string($0.description), "parameters": $0.schema])]) }) }
            if let decision = r.reasoningDecision { ReasoningPolicy.apply(decision,to:&b,format:r.profile.format) }
            if r.profile.preset == .openAI, r.reasoningDecision?.kind == .openAI {
                b["max_tokens"] = nil; b["max_completion_tokens"] = .number(Double(r.outputBudget))
            }
            return .object(b)
        case .anthropic:
            let rows: [JSON] = messages.map { m in
                if m.role == .tool { return .object(["role": "user", "content": .array([.object(["type": "tool_result", "tool_use_id": .string(m.toolCallID ?? ""), "content": .string(m.text)])])]) }
                var blocks: [JSON] = m.providerContinuation?.payload(for:r)?["anthropic"].array ?? []
                if !m.text.isEmpty { blocks.append(.object(["type": "text", "text": .string(m.text)])) }
                blocks += m.calls.map { .object(["type": "tool_use", "id": .string($0.id), "name": .string($0.name), "input": $0.arguments]) }
                return .object(["role": .string(m.role == .assistant ? "assistant" : "user"), "content": .array(blocks)])
            }
            var b: [String: JSON] = ["model": .string(r.model), "system": .string(system), "messages": .array(rows), "max_tokens": .number(Double(r.outputBudget)), "stream": true]
            if !r.tools.isEmpty { b["tools"] = .array(r.tools.map { .object(["name": .string($0.name), "description": .string($0.description), "input_schema": $0.schema]) }) }
            if let decision = r.reasoningDecision { ReasoningPolicy.apply(decision,to:&b,format:r.profile.format) }
            return .object(b)
        case .gemini:
            let rows: [JSON] = messages.map { m in
                if m.role == .tool { return .object(["role": "user", "parts": .array([.object(["functionResponse": .object(["name": .string(m.calls.first?.name ?? m.toolCallID ?? "tool"), "response": .object(["result": .string(m.text)])])])])]) }
                var parts: [JSON] = m.text.isEmpty ? [] : [.object(["text": .string(m.text)])]
                if let preserved = m.providerContinuation?.payload(for:r)?["gemini"].array {
                    parts += preserved
                    let preservedNames = Set(preserved.compactMap { $0["functionCall"]["name"].string })
                    parts += m.calls.filter { !preservedNames.contains($0.name) }.map { .object(["functionCall": .object(["name": .string($0.name), "args": $0.arguments])]) }
                } else { parts += m.calls.map { .object(["functionCall": .object(["name": .string($0.name), "args": $0.arguments])]) } }
                return .object(["role": .string(m.role == .assistant ? "model" : "user"), "parts": .array(parts)])
            }
            var b: [String: JSON] = ["contents": .array(rows), "systemInstruction": .object(["parts": .array([.object(["text": .string(system)])])]), "generationConfig": .object(["maxOutputTokens": .number(Double(r.outputBudget))])]
            if !r.tools.isEmpty { b["tools"] = .array([.object(["functionDeclarations": .array(r.tools.map { .object(["name": .string($0.name), "description": .string($0.description), "parameters": $0.schema]) })])]) }
            if let decision = r.reasoningDecision { ReasoningPolicy.apply(decision,to:&b,format:r.profile.format) }
            return .object(b)
        }
    }
    public static func request(_ r: RunRequest, key: String) throws -> URLRequest {
        let r = ProviderRouting.prepare(r)
        if r.profile.preset == .openAI,r.profile.format == .chatCompletions,!r.tools.isEmpty,
           r.model.hasPrefix("gpt-6-astra") || r.model.hasPrefix("gpt-6.1-sol") { throw RMError.unsupported }
        try ProviderDisclosure.validate(profile:r.profile,model:r.model)
        guard !key.isEmpty else { throw RMError.consentRequired }
        guard let base = URL(string: r.profile.endpoint) else { throw RMError.invalidInput }; try URLPolicy.validate(base)
        let segments: [String]
        switch r.profile.format {
        case .responses: segments = ["responses"]; case .chatCompletions: segments = ["chat", "completions"]
        case .anthropic: segments = ["messages"]; case .gemini: segments = ["models", "\(r.model.replacingOccurrences(of: "models/", with: "")):streamGenerateContent"]
        }
        var request = URLRequest(url: try URLPolicy.append(base, segments: segments, query: r.profile.format == .gemini ? ["alt": "sse"] : [:]))
        request.httpMethod = "POST"; request.httpBody = try body(r).encoded
        request.setValue("RepoManager/1.0",forHTTPHeaderField:"User-Agent")
        if r.profile.preset == .openCodeGo || r.profile.preset == .openCodeZen { request.setValue(r.conversationID.uuidString,forHTTPHeaderField:"x-opencode-session") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        switch r.profile.format {
        case .anthropic: request.setValue(key, forHTTPHeaderField: "x-api-key"); request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        default: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
public struct CloudProviderClient: ProviderClient {
    private let transport: any HTTPTransport; private let secrets: any SecretStore
    public init(transport: any HTTPTransport = SecureHTTPTransport(), secrets: any SecretStore = KeychainStore()) { self.transport = transport; self.secrets = secrets }
    public func stream(_ request: RunRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let request = ProviderRouting.prepare(request)
        return AsyncThrowingStream(bufferingPolicy:.bufferingOldest(64)) { continuation in
            let task = Task {
                do {
                    guard !request.profile.usesChatGPT else { throw RMError.invalidInput }
                    guard let data = try secrets.read("provider:\(request.profile.id)"), let key = String(data: data, encoding: .utf8) else { throw RMError.authentication }
                    let http = try ProviderWire.request(request, key: key)
                    var parser = SSEParser(); var decoder = ProviderEventDecoder(format: request.profile.format)
                    for try await chunk in transport.stream(http, limit: 8 * 1024 * 1024) {
                        try Task.checkCancellation()
                        for frame in try parser.feed(chunk) { for event in try decoder.decode(frame) { try StreamDelivery.yield(event,to:continuation) } }
                    }
                    for frame in try parser.feed(Data(), final: true) { for event in try decoder.decode(frame) { try StreamDelivery.yield(event,to:continuation) } }
                    guard decoder.completed else { throw RMError.connection }
                    continuation.finish()
                } catch is CancellationError { continuation.finish(throwing:RMError.cancelled) }
                catch { continuation.finish(throwing: error as? RMError ?? .connection) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    public func catalog(_ profile: ProviderProfile) async throws -> [ModelMetadata] {
        guard !profile.usesChatGPT else { throw RMError.invalidInput }
        guard profile.consentEndpoint == profile.endpoint else { throw RMError.consentRequired }
        guard let base = URL(string: profile.endpoint), let key = try secrets.read("provider:\(profile.id)"), let token = String(data: key, encoding: .utf8) else { throw RMError.authentication }
        var results: [ModelMetadata] = []; var cursor: String?; var seen = Set<String>()
        for _ in 0..<20 {
            var query: [String: String] = [:]
            if let cursor { query[profile.format == .gemini ? "pageToken" : "after_id"] = cursor }
            if profile.format == .gemini { query["pageSize"] = "100" }
            else if profile.format == .anthropic { query["limit"] = "100" }
            var request = URLRequest(url: try URLPolicy.append(base, segments: ["models"], query: query))
            if profile.format == .gemini { request.setValue(token, forHTTPHeaderField: "x-goog-api-key") }
            else if profile.format == .anthropic { request.setValue(token, forHTTPHeaderField: "x-api-key"); request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
            else { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            let result = try await transport.send(request, limit: 4 * 1024 * 1024); try SecureHTTPTransport.checkStatus(result.status)
            let root = try JSON.parse(result.data)
            for row in root[profile.format == .gemini ? "models" : "data"].array ?? [] {
                if let id = row["id"].string ?? row["name"].string, !seen.contains(id) {
                    _ = try InputValidation.model(id); seen.insert(id)
                    if let metadata = try ProviderRouting.metadata(row,profile:profile) { results.append(metadata) }
                }
            }
            guard results.count <= 2000 else { throw RMError.tooLarge }
            let next = root["nextPageToken"].string ?? (root["has_more"].bool == true ? root["last_id"].string : nil)
            guard let next, next != cursor else { return results.sorted { $0.id < $1.id } }; cursor = next
        }
        return results.sorted { $0.id < $1.id }
    }
}
public enum ContextBudget {
    public static func validate(_ request: RunRequest) throws {
        let cost = request.messages.reduce(0) { $0 + estimate($1) } + request.tools.reduce(0) { $0 + ToolSelection.cost($1) + 40 }
        guard request.inputBudget > 0, request.outputBudget > 0, cost <= request.inputBudget,
              request.messages.contains(where:{ $0.role == .user }) else { throw RMError.tooLarge }
    }
    public static func prepare(_ request: RunRequest) -> RunRequest {
        var r = request
        if let m = r.profile.models.first(where: { $0.id == r.model }) {
            r.outputBudget = min(r.outputBudget, m.outputTokens ?? r.outputBudget)
            if let c = m.contextTokens { r.outputBudget = min(r.outputBudget, max(1, c / 3)); r.inputBudget = min(r.inputBudget, max(1, c - r.outputBudget - 512)) }
        }
        let toolCost = r.tools.reduce(0) { $0 + ToolSelection.cost($1) + 40 }
        let systems = r.messages.filter { $0.role == .system }
        var remaining = max(0, r.inputBudget - toolCost - systems.reduce(0) { $0 + estimate($1) })
        var kept: [ChatMessage] = []
        // Keep assistant tool calls together with all their results.
        let history = r.messages.filter { $0.role != .system }
        var groups: [[ChatMessage]] = []
        for m in history {
            if m.role == .tool && !groups.isEmpty { groups[groups.count-1].append(m) } else { groups.append([m]) }
        }
        for group in groups.reversed() {
            let cost = group.reduce(0) { $0 + estimate($1) }
            if cost > remaining { break }; remaining -= cost; kept.insert(contentsOf: group, at: 0)
        }
        r.messages = systems + kept
        return r
    }
    public static func estimate(_ m: ChatMessage) -> Int { (m.text.utf8.count + m.calls.reduce(0) { $0 + $1.arguments.encoded.count }) / 3 + 16 }
}

/// Compatibility mode accepts only one complete, dedicated tool fence and no quoted/prose examples.
public enum TextToolBridge {
    public static func call(_ answer: String, allowedNames: Set<String>) -> ToolCall? {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains("<think>"), !text.contains("</think>"), text.hasPrefix("```tool\n"), text.hasSuffix("\n```"),
              text.components(separatedBy: "```").count == 3,
              let json = try? JSON.parse(Data(text.dropFirst(8).dropLast(4).utf8)),
              let name = json["name"].string, allowedNames.contains(name), let args = json["arguments"].object else { return nil }
        return ToolCall(name: name, arguments: .object(args))
    }
}


public enum ToolSelection {
    public static func cost(_ definition:ToolDefinition) -> Int { (definition.schema.encoded.count+definition.name.utf8.count+definition.description.utf8.count)/3+40 }
    public static func select(_ definitions:[ToolDefinition],request:RunRequest) -> [ToolDefinition] {
        let effective = ContextBudget.prepare(request)
        let budget = max(0,min(3000,effective.inputBudget/3))
        let text = request.messages.suffix(6).map(\.text).joined(separator:" ").lowercased()
        let terms = text.split(whereSeparator:{ !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init)
        let essential: Set<String> = ["find_tools","list_files","read_file","git_diff","repository_info","request_user_approval","write_file","replace_text","checkpoint","calculator","datetime"]
        func score(_ d:ToolDefinition) -> Int {
            var value = essential.contains(d.name) ? 8 : 0
            if d.name == "find_tools" { value += 100 }
            if text.contains(d.name) { value += 60 }
            let words = (d.name+" "+d.group).lowercased().replacingOccurrences(of:"_",with:" ")
            value += terms.filter { $0.count > 3 && words.contains($0) }.count*4
            return value
        }
        let ranked = definitions.sorted { score($0) == score($1) ? $0.name < $1.name : score($0) > score($1) }
        var selected:[ToolDefinition] = []; var used = 0
        for d in ranked { let cost = cost(d); if used+cost <= budget { selected.append(d); used += cost } }
        return selected
    }
}
