import Foundation

public struct APIClientGrant: Codable, Identifiable, Sendable {
    public var id = UUID(); public var name: String; public var providerIDs: Set<UUID>
    public var repository: RepositoryScope?; public var tools: Set<String>; public var revoked = false; public var created = Date()
    public init(name: String, providerIDs: Set<UUID>, repository: RepositoryScope?, tools: Set<String>) { self.name = name; self.providerIDs = providerIDs; self.repository = repository; self.tools = tools }
}
public struct AgentSession: Codable, Identifiable, Sendable {
    public var id = UUID(); public var owner: UUID; public var providerID: UUID; public var model: String
    public var repository: RepositoryScope?; public var mode: RunMode; public var created = Date()
    public init(owner: UUID, providerID: UUID, model: String, repository: RepositoryScope?, mode: RunMode) { self.owner = owner; self.providerID = providerID; self.model = model; self.repository = repository; self.mode = mode }
}
public struct AgentRunSnapshot: Codable, Identifiable, Sendable {
    public var id = UUID(); public var owner: UUID; public var sessionID: UUID; public var state = "running"
    public var text = ""; public var reasoning = ""; public var tools: [ToolResult] = []; public var usage: Usage?
    public var error: String?; public var created = Date()
    public init(owner: UUID, sessionID: UUID) { self.owner = owner; self.sessionID = sessionID }
}
public struct APIRequest: Sendable {
    public var method: String; public var path: String; public var headers: [String:String]; public var body: Data
    public init(method: String, path: String, headers: [String:String], body: Data = Data()) { self.method = method; self.path = path; self.headers = headers; self.body = body }
}
public struct APIResponse: Sendable {
    public var status: Int; public var body: Data; public var contentType: String
    public var stream: AsyncThrowingStream<Data,Error>?
    public init(status: Int = 200, json: JSON) { self.status = status; body = json.encoded; contentType = "application/json"; stream = nil }
    public init(stream: AsyncThrowingStream<Data,Error>, contentType: String = "text/event-stream") { status = 200; body = Data(); self.contentType = contentType; self.stream = stream }
}
public actor APIAuthorization {
    private let secrets: any SecretStore; private let vault: SecureStore
    private var grants: [APIClientGrant] = []; private var attempts: [String:(Date,Int)] = [:]
    public init(vault: SecureStore, secrets: any SecretStore = KeychainStore()) { self.vault = vault; self.secrets = secrets }
    public func restore() async throws { grants = try await vault.load([APIClientGrant].self,id:"api-grants") ?? [] }
    public func clients() -> [APIClientGrant] { grants }
    public func create(_ grant: APIClientGrant) async throws -> String {
        guard grants.count < 100,!grants.contains(where:{ $0.id == grant.id }),!grant.name.isEmpty,grant.name.utf8.count <= 200,
              !grant.tools.contains(where:{ (try? ToolCatalog.named($0)).map { !ExternalToolPolicy.permits($0) } ?? true }) else { throw RMError.invalidInput }
        let key = try RecordCrypto.random(32).base64EncodedString()
        try secrets.write(Data(key.utf8),account:"api-client:\(grant.id)")
        grants.append(grant); try await vault.save(grants,id:"api-grants")
        return "\(grant.id.uuidString).\(key)"
    }
    public func revoke(_ id: UUID) async throws {
        guard let i = grants.firstIndex(where:{ $0.id == id }) else { throw RMError.invalidInput }
        grants[i].revoked = true
        try await vault.save(grants,id:"api-grants")
        try secrets.delete("api-client:\(id)")
    }
    public func authenticate(_ header: String?, source: String = "local") throws -> APIClientGrant {
        attempts = attempts.filter { Date().timeIntervalSince($0.value.0) < 60 }
        guard source.utf8.count <= 256,attempts[source] != nil || attempts.count < 1024 else { throw RMError.rateLimited }
        let now = Date(); let old = attempts[source] ?? (now,0)
        if now.timeIntervalSince(old.0) < 60 && old.1 >= 10 { throw RMError.rateLimited }
        guard let header, header.hasPrefix("Bearer "), header.count <= 500 else { fail(source,now); throw RMError.authentication }
        let parts = String(header.dropFirst(7)).split(separator:".",maxSplits:1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString:parts[0]), let grant = grants.first(where:{ $0.id == id && !$0.revoked }),
              let key = try secrets.read("api-client:\(id)"), RecordCrypto.constantTimeEqual(Data(parts[1].utf8),key) else { fail(source,now); throw RMError.authentication }
        attempts[source] = nil; return grant
    }
    private func fail(_ source: String, _ now: Date) {
        let previous = attempts[source]; attempts[source] = previous.map { now.timeIntervalSince($0.0) < 60 ? ($0.0,$0.1+1) : (now,1) } ?? (now,1)
    }
}

public enum Compatibility {
    public static func reasoning(_ body:JSON) throws -> ReasoningPreference? {
        for key in ["reasoning","output_config"] where body[key] != .null { guard body[key].object != nil else { throw RMError.invalidInput } }
        for value in [body["reasoning"]["effort"],body["reasoning"]["summary"],body["reasoning_effort"],body["output_config"]["effort"]] where value != .null { guard value.string != nil else { throw RMError.invalidInput } }
        if body["reasoning"].object?.keys.contains(where:{ !["effort","summary"].contains($0) }) == true ||
           body["output_config"].object?.keys.contains(where:{ $0 != "effort" }) == true { throw RMError.unsupported }
        if let summary = body["reasoning"]["summary"].string, !["auto","concise","detailed"].contains(summary) { throw RMError.unsupported }
        let options = [body["reasoning"]["effort"].string,body["reasoning_effort"].string,body["output_config"]["effort"].string].compactMap { $0 }
        guard Set(options).count <= 1 else { throw RMError.invalidInput }
        if let effort = options.first {
            if effort == "none" { return .off }
            guard let value = ReasoningPreference(rawValue:effort) else { throw RMError.unsupported }; return value
        }
        if body["thinking"] != .null {
            guard let kind = body["thinking"]["type"].string, body["thinking"].object?.keys.allSatisfy({ $0 == "type" }) == true else { throw RMError.unsupported }
            switch kind { case "adaptive","enabled": return .automatic; case "disabled": return .off; default: throw RMError.unsupported }
        }
        return nil
    }
    public static func messages(_ body: JSON, format: String) throws -> [ChatMessage] {
        guard body["images"] == .null, body["audio"] == .null, body["modalities"] == .null else { throw RMError.unsupported }
        var messages: [ChatMessage] = []
        if let system = body["system"].string ?? body["instructions"].string { messages.append(ChatMessage(role:.system,text:system)) }
        if format == "responses", let input = body["input"].string { messages.append(ChatMessage(role:.user,text:input)); return messages }
        if format == "generate" { guard let prompt = body["prompt"].string else { throw RMError.invalidInput }; messages.append(ChatMessage(role:.user,text:prompt)); return messages }
        let rows = body[format == "responses" ? "input" : "messages"].array ?? []
        guard rows.count <= 500 else { throw RMError.tooLarge }
        for row in rows {
            guard row["images"] == .null, row["audio"] == .null else { throw RMError.unsupported }
            if format == "responses", row["type"].string == "function_call" {
                var call = ChatMessage(role:.assistant); call.calls = [try toolCall(row,responses:true)]; messages.append(call); continue
            }
            if format == "responses", row["type"].string == "function_call_output" {
                guard let id = row["call_id"].string, let output = row["output"].string else { throw RMError.unsupported }
                messages.append(ChatMessage(role:.tool,text:output,toolCallID:id)); continue
            }
            guard let role = row["role"].string, let r = MessageRole(rawValue:role) else { throw RMError.unsupported }
            var message = ChatMessage(role:r,toolCallID:row["tool_call_id"].string)
            if let value = row["content"].string { message.text = value }
            else if let blocks = row["content"].array {
                for block in blocks {
                    switch block["type"].string {
                    case "text","input_text","output_text": guard let text = block["text"].string else { throw RMError.invalidInput }; message.text += text
                    case "tool_use":
                        guard format == "anthropic", r == .assistant, let id = block["id"].string, let name = block["name"].string, block["input"].object != nil else { throw RMError.unsupported }
                        message.calls.append(ToolCall(id:id,name:name,arguments:block["input"]))
                    case "tool_result":
                        guard format == "anthropic", r == .user, let id = block["tool_use_id"].string else { throw RMError.unsupported }
                        let output: String
                        if let text = block["content"].string { output = text }
                        else if let content = block["content"].array, content.allSatisfy({ $0["type"].string == "text" }) { output = content.compactMap { $0["text"].string }.joined(separator:"\n") }
                        else { throw RMError.unsupported }
                        messages.append(ChatMessage(role:.tool,text:output,toolCallID:id))
                    default: throw RMError.unsupported
                    }
                }
            } else if row["content"] != .null { throw RMError.invalidInput }
            if let calls = row["tool_calls"].array {
                guard r == .assistant, calls.count <= 100 else { throw RMError.invalidInput }
                message.calls = try calls.map { try toolCall($0,responses:false,ollama:format == "ollamaChat") }
            }
            if !message.text.isEmpty || !message.calls.isEmpty || r == .tool { messages.append(message) }
        }
        var known: [String:ToolCall] = [:]; var completed = Set<String>()
        for i in messages.indices {
            for call in messages[i].calls { guard known[call.id] == nil else { throw RMError.invalidInput }; known[call.id] = call }
            if messages[i].role == .tool {
                let id: String
                if let supplied = messages[i].toolCallID { id = supplied }
                else if format == "ollamaChat", let unmatched = known.keys.sorted().first(where:{ !completed.contains($0) }) { id = unmatched; messages[i].toolCallID = id }
                else { throw RMError.invalidInput }
                guard let call = known[id], !completed.contains(id) else { throw RMError.invalidInput }; completed.insert(id); messages[i].calls = [call]
            }
        }
        guard Set(known.keys) == completed, messages.contains(where:{ $0.role == .user }), messages.reduce(0,{ $0+$1.text.utf8.count+$1.calls.reduce(0,{ $0+$1.arguments.encoded.count }) }) <= 1024*1024 else { throw RMError.invalidInput }
        return messages
    }
    private static func toolCall(_ row: JSON, responses: Bool, ollama: Bool = false) throws -> ToolCall {
        let function = responses ? row : row["function"]
        guard let name = function["name"].string, !name.isEmpty, name.count <= 100 else { throw RMError.invalidInput }
        let args: JSON
        if let text = function["arguments"].string { args = try JSON.parse(Data(text.utf8)) }
        else if ollama { args = function["arguments"] }
        else { throw RMError.invalidInput }
        guard args.object != nil else { throw RMError.invalidInput }
        let id = (responses ? row["call_id"].string : row["id"].string) ?? (ollama ? UUID().uuidString : "")
        guard !id.isEmpty, id.count <= 200 else { throw RMError.invalidInput }
        return ToolCall(id:id,name:name,arguments:args)
    }
    public static func toolDefinitions(_ body: JSON) throws -> [ToolDefinition] {
        guard let list = body["tools"].array else { return [] }; guard list.count <= 100 else { throw RMError.tooLarge }
        return try list.map { row in
            let f = row["function"].object != nil ? row["function"] : row
            guard let name = f["name"].string, name.count <= 100, let schema = (f["parameters"].object != nil ? f["parameters"] : f["input_schema"]).object else { throw RMError.invalidInput }
            return ToolDefinition(name:name,group:"Client",description:f["description"].string ?? "Client-owned tool",schema:.object(schema))
        }
    }
    public static func frame(_ json: JSON, event: String? = nil, ndjson: Bool = false) -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let raw = (try? e.encode(json)) ?? Data("{}".utf8)
        if ndjson { return raw+Data([10]) }
        return Data(((event.map { "event: \($0)\n" } ?? "")+"data: ").utf8)+raw+Data([10,10])
    }
}
public actor AgentAPI {
    private let auth: APIAuthorization; private let runs: RunCoordinator; private let tools: ToolRegistry; private let approvals: ApprovalCoordinator
    private var profiles: [ProviderProfile] = []; private var sessions: [UUID:AgentSession] = [:]
    private var snapshots: [UUID:AgentRunSnapshot] = [:]; private var runTasks: [UUID:Task<Void,Never>] = [:]
    private var compatibilityRuns = Set<UUID>()
    private var epoch:UInt64 = 0; private var deniedClients = Set<UUID>()
    private var directTasks:[UUID:Task<ToolResult,Never>] = [:]
    private var directResults:[String:(digest:String,result:ToolResult)] = [:]
    private var requestWindows:[UUID:(Date,Int)] = [:]
    private var eventBytes:[UUID:Int] = [:]
    private var activeCount:Int { runTasks.count + compatibilityRuns.count + directTasks.count }
    private var events: [UUID:[JSON]] = [:]; private var idempotency: [String:(String,UUID)] = [:]
    public init(auth: APIAuthorization, runs: RunCoordinator, tools: ToolRegistry, approvals: ApprovalCoordinator) { self.auth = auth; self.runs = runs; self.tools = tools; self.approvals = approvals }
    public func configure(profiles: [ProviderProfile]) async { if self.profiles != profiles { await stop() }; self.profiles = profiles }
    public func revokeClient(_ id:UUID) async throws {
        deniedClients.insert(id)
        await stop() // Invalidate and cancel work before the Keychain/persistence await.
        try await auth.revoke(id)
    }
    public func stop() async {
        epoch &+= 1
        let running = runTasks.values; let direct = directTasks.values
        let previousIDs = Set(sessions.keys).union(compatibilityRuns)
        sessions.removeAll(); snapshots.removeAll(); events.removeAll(); eventBytes.removeAll()
        runTasks.removeAll(); directTasks.removeAll(); compatibilityRuns.removeAll(); idempotency.removeAll(); directResults.removeAll()
        for task in running { task.cancel() }; for task in direct { task.cancel() }
        for id in previousIDs { await runs.cancel(id); await approvals.invalidate(conversationID:id); await approvals.bind(id,scope:nil) }
    }
    public func handle(_ request: APIRequest, source: String = "local") async -> APIResponse {
        let lease = epoch
        do {
            guard request.body.count <= 1024*1024, !request.path.contains("?"), !request.path.contains("%"), !request.path.contains("..") else { throw RMError.invalidInput }
            let grant = try await auth.authenticate(request.headers["authorization"],source:source)
            guard lease == epoch,!deniedClients.contains(grant.id) else { throw RMError.authentication }
            let now = Date(),previous = requestWindows[grant.id] ?? (Date(),0)
            let count = now.timeIntervalSince(previous.0) < 60 ? previous.1+1 : 1
            guard count <= 60 else { throw RMError.rateLimited }; requestWindows[grant.id] = (count == 1 ? now : previous.0,count)
            let body = request.body.isEmpty ? JSON.object([:]) : try JSON.parse(request.body)
            let response = try await route(request,body:body,grant:grant)
            let valid = await auth.clients().contains { $0.id == grant.id && !$0.revoked }
            guard lease == epoch,valid,!deniedClients.contains(grant.id) else { throw RMError.authentication }
            return response
        } catch {
            let e = error as? RMError ?? .invalidInput
            let code = e == .authentication ? 401 : e == .forbidden || e == .proRequired ? 403 : e == .rateLimited ? 429 : e == .staleReview || e == .conflict ? 409 : 400
            return APIResponse(status:code,json:.object(["error":.object(["type":.string(e.rawValue),"message":.string(e.localizedDescription)])]))
        }
    }
    private func route(_ request: APIRequest, body: JSON, grant: APIClientGrant) async throws -> APIResponse {
        let path = request.path
        if request.method == "GET", ["/v1/models","/api/tags","/v1/capabilities","/api/version","/api/ps"].contains(path) {
            if path == "/api/version" { return APIResponse(json:.object(["version":"RepoManager/1.0","local_runtimes":false])) }
            if path == "/api/ps" { return APIResponse(json:.object(["models":.array([])])) }
            if path == "/v1/capabilities" { return APIResponse(json:.object(["version":1,"https":true,"text":true,"tools":true,"native_approval_required":true,"local_runtimes":false,"history_access":false])) }
            let models = try profiles.filter { grant.providerIDs.contains($0.id) }.flatMap { p in try p.models.map { m in JSON.object(["id":.string("\(p.id.uuidString)/\(m.id)"),"name":.string("\(p.id.uuidString)/\(m.id)"),"object":"model","owned_by":.string(p.title),"metadata":try encoded(m)]) } }
            return APIResponse(json:.object([path == "/api/tags" ? "models" : "data":.array(models),"object":"list"]))
        }
        if request.method == "POST", path == "/api/show" {
            guard body.object?.keys.allSatisfy({ $0 == "model" }) == true else { throw RMError.unsupported }
            let (profile,model) = try selected(body["model"].string,grant:grant)
            return APIResponse(json:.object(["model":.string(model),"capabilities":.array(["completion","tools"]),"local":false,
                "metadata":try encoded(profile.models.first { $0.id == model } ?? ModelMetadata(id:model))]))
        }
        if request.method == "POST", ["/v1/chat/completions","/v1/responses","/v1/messages","/api/chat","/api/generate"].contains(path) {
            return try await compatibility(request,body:body,grant:grant)
        }
        if request.method == "POST", path == "/v1/agent/sessions" {
            guard body.object?.keys.allSatisfy({ ["model","mode"].contains($0) }) == true, sessions.count < 64 else { throw RMError.invalidInput }
            if body["mode"] != .null { guard let mode = body["mode"].string,RunMode(rawValue:mode) != nil else { throw RMError.unsupported } }
            let (profile,model) = try selected(body["model"].string,grant:grant)
            let session = AgentSession(owner:grant.id,providerID:profile.id,model:model,repository:grant.repository,mode:body["mode"].string == "act" ? .act : .plan)
            sessions[session.id] = session; await approvals.bind(session.id,scope:session.repository)
            return APIResponse(status:201,json:try encoded(session))
        }
        let parts = path.split(separator:"/").map(String.init)
        guard parts.count >= 4, Array(parts.prefix(3)) == ["v1","agent","sessions"], let id = UUID(uuidString:parts[3]),
              let session = sessions[id], session.owner == grant.id else { throw RMError.forbidden }
        let context = ScopedToolContext(conversationID:id,repository:session.repository,mode:session.mode,allowedTools:grant.tools)
        if parts.count == 5, parts[4] == "tools", request.method == "GET" { return APIResponse(json:try encoded(await tools.available(context:context))) }
        if parts.count == 6, parts[4] == "tools", parts[5] == "execute", request.method == "POST" {
            guard let name = body["name"].string, body.object?.keys.allSatisfy({ ["name","arguments"].contains($0) }) == true else { throw RMError.invalidInput }
            let key = request.headers["idempotency-key"]
            if let key { guard !key.isEmpty,key.utf8.count <= 200 else { throw RMError.invalidInput } }
            let cacheID = key.map { "\(grant.id):\(id):\($0)" },digest = RecordCrypto.digest(request.body)
            if let cacheID,let previous = directResults[cacheID] {
                guard previous.digest == digest else { throw RMError.conflict }
                return APIResponse(json:try encoded(previous.result))
            }
            guard activeCount < 4,directTasks[id] == nil,!runTasks.keys.contains(where:{ snapshots[$0]?.sessionID == id }) else { throw RMError.rateLimited }
            guard cacheID == nil || directResults.count < 64 else { throw RMError.rateLimited }
            let lease = epoch
            let task = Task { await self.tools.execute(ToolCall(name:name,arguments:body["arguments"]),context:context) }
            directTasks[id] = task
            let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard lease == epoch else { throw RMError.cancelled }; directTasks[id] = nil
            guard result.detail.utf8.count <= 512*1024 else { throw RMError.tooLarge }
            if let cacheID { directResults[cacheID] = (digest,result) }
            return APIResponse(json:try encoded(result))
        }
        if parts.count == 5, parts[4] == "approvals", request.method == "GET" {
            let reviews = await approvals.pending(conversationID:id)
            return APIResponse(json:.array(reviews.map { p in
                .object(["id":.string(p.id.uuidString),"scope":(try? encoded(p.scope)) ?? .null,"operation":.string(p.operation),
                    "risk":.string(p.risk.rawValue),"arguments":GitHubRedaction.clean(p.arguments),"before":p.before,
                    "expires":.number(p.expires.timeIntervalSince1970),"approval":"native_only",
                    "changes":.array(p.draft?.changes.map { .object(["path":.string($0.path),"diff":.string(TextDiff.review($0)),"mode":.string($0.mode)]) } ?? [])])
            }))
        }
        if parts.count == 5, parts[4] == "operations", request.method == "GET" {
            let journal = await approvals.journal()
            return APIResponse(json:try encoded(journal.filter { $0.conversationID == id }))
        }
        if parts.count == 5, parts[4] == "runs", request.method == "POST" {
            guard snapshots.count < 32, body.object?.keys.allSatisfy({ ["messages","reasoning","reasoning_effort"].contains($0) }) == true else { throw RMError.invalidInput }
            let digest = RecordCrypto.digest(request.body)
            if let key = request.headers["idempotency-key"] {
                guard key.count <= 200 else { throw RMError.invalidInput }
                if let previous = idempotency["\(grant.id):\(id):\(key)"] { guard previous.0 == digest, let snapshot = snapshots[previous.1] else { throw RMError.conflict }; return APIResponse(json:try encoded(snapshot)) }
            }
            guard activeCount < 4,directTasks[id] == nil,!runTasks.keys.contains(where:{ snapshots[$0]?.sessionID == id }) else { throw RMError.rateLimited }
            let messages = try Compatibility.messages(body,format:"chat")
            guard let profile = profiles.first(where:{ $0.id == session.providerID }), grant.providerIDs.contains(profile.id) else { throw RMError.forbidden }
            let snapshot = AgentRunSnapshot(owner:grant.id,sessionID:id); snapshots[snapshot.id] = snapshot; events[snapshot.id] = []; eventBytes[snapshot.id] = 0
            if let key = request.headers["idempotency-key"] { idempotency["\(grant.id):\(id):\(key)"] = (digest,snapshot.id) }
            var input = RunRequest(conversationID:id,profile:profile,model:session.model,messages:messages)
            input.reasoningPreference = try Compatibility.reasoning(body)
            runTasks[snapshot.id] = Task { await self.consume(snapshot.id,input:input,context:context) }
            return APIResponse(status:202,json:try encoded(snapshot))
        }
        if parts.count >= 6, parts[4] == "runs", let runID = UUID(uuidString:parts[5]), let snapshot = snapshots[runID], snapshot.owner == grant.id, snapshot.sessionID == id {
            if parts.count == 6 && request.method == "GET" { return APIResponse(json:try encoded(snapshot)) }
            if parts.count == 7, parts[6] == "cancel", request.method == "POST" {
                runTasks[runID]?.cancel(); snapshots[runID]?.state = "cancelled"
                await runs.cancel(id); return APIResponse(json:.object(["cancelled":true]))
            }
            if parts.count == 7, parts[6] == "events", request.method == "GET" { return APIResponse(stream:eventStream(runID,grantID:grant.id)) }
        }
        throw RMError.unsupported // Includes every possible remote approval path/flag.
    }
    private func selected(_ value: String?, grant: APIClientGrant) throws -> (ProviderProfile,String) {
        guard let value, let slash = value.firstIndex(of:"/"), let id = UUID(uuidString:String(value[..<slash])), grant.providerIDs.contains(id),
              let profile = profiles.first(where:{ $0.id == id }), profile.consentEndpoint == profile.endpoint else { throw RMError.forbidden }
        let model = try InputValidation.model(String(value[value.index(after:slash)...])); return (profile,model)
    }
    private func compatibility(_ request: APIRequest, body: JSON, grant: APIClientGrant) async throws -> APIResponse {
        let allowed: Set<String> = ["model","messages","input","instructions","system","prompt","stream","max_tokens","max_output_tokens","tools","tool_choice","store","reasoning","reasoning_effort","thinking","output_config"]
        guard body.object?.keys.allSatisfy(allowed.contains) == true, body["store"].bool != true,
              body["tool_choice"] == .null || body["tool_choice"].string == "auto" else { throw RMError.unsupported }
        for key in ["stream","store"] where body[key] != .null { guard body[key].bool != nil else { throw RMError.invalidInput } }
        for key in ["max_tokens","max_output_tokens"] where body[key] != .null { guard let limit = body[key].int,(1...4096).contains(limit) else { throw RMError.invalidInput } }
        for key in ["instructions","system","prompt"] where body[key] != .null { guard body[key].string != nil else { throw RMError.unsupported } }
        if body["tools"] != .null { guard body["tools"].array != nil else { throw RMError.invalidInput } }
        _ = try Compatibility.reasoning(body)
        let (profile,model) = try selected(body["model"].string,grant:grant)
        let format = request.path == "/v1/responses" ? "responses" : request.path == "/v1/messages" ? "anthropic" : request.path == "/api/generate" ? "generate" : request.path == "/api/chat" ? "ollamaChat" : "chat"
        let messages = try Compatibility.messages(body,format:format)
        let definitions = try Compatibility.toolDefinitions(body)
        guard format != "generate" || definitions.isEmpty else { throw RMError.unsupported }
        guard activeCount < 4 else { throw RMError.rateLimited }
        let lease = epoch
        let sessionID = UUID(); compatibilityRuns.insert(sessionID)
        var input = RunRequest(conversationID:sessionID,profile:profile,model:model,messages:messages,tools:definitions,outputBudget:body["max_output_tokens"].int ?? body["max_tokens"].int ?? 4096)
        input.reasoningPreference = try Compatibility.reasoning(body)
        input.executeTools = false
        let context = ScopedToolContext(conversationID:sessionID,repository:nil,mode:.plan,allowedTools:[])
        let stream = await runs.stream(input,context:context)
        if body["stream"].bool == true { return APIResponse(stream:wireStream(stream,format:format,model:body["model"].string ?? model,sessionID:sessionID,grantID:grant.id,lease:lease),contentType:["generate","ollamaChat"].contains(format) ? "application/x-ndjson" : "text/event-stream") }
        defer { compatibilityRuns.remove(sessionID) }
        var wire = CompatibilityWire(format:format,model:body["model"].string ?? model)
        for try await event in stream {
            try Task.checkCancellation(); guard epoch == lease,!deniedClients.contains(grant.id) else { throw RMError.cancelled }
            _ = wire.consume(event)
        }
        return APIResponse(json:wire.completed())
    }
    private func wireStream(_ stream:AsyncThrowingStream<ChatEvent,Error>,format:String,model:String,sessionID:UUID,grantID:UUID,lease:UInt64) -> AsyncThrowingStream<Data,Error> {
        AsyncThrowingStream(bufferingPolicy:.bufferingOldest(32)) { continuation in
            let task = Task {
                var wire = CompatibilityWire(format:format,model:model)
                do {
                    for data in wire.start() { try Self.yield(data,to:continuation) }
                    for try await event in stream {
                        try Task.checkCancellation()
                        let valid = await self.auth.clients().contains { $0.id == grantID && !$0.revoked }
                        guard self.epoch == lease,valid,!self.deniedClients.contains(grantID) else { throw RMError.cancelled }
                        for data in wire.consume(event) { try Self.yield(data,to:continuation) }
                    }
                    for data in wire.finish() { try Self.yield(data,to:continuation) }
                    continuation.finish()
                } catch { continuation.finish(throwing:error as? RMError ?? .connection) }
                self.compatibilityRuns.remove(sessionID); await self.runs.cancel(sessionID)
            }
            continuation.onTermination = { _ in task.cancel(); Task { await self.runs.cancel(sessionID) } }
        }
    }
    private static func yield(_ data:Data,to continuation:AsyncThrowingStream<Data,Error>.Continuation) throws {
        guard data.count <= 2*1024*1024 else { throw RMError.tooLarge }
        switch continuation.yield(data) {
        case .enqueued: break
        case .dropped: throw RMError.tooLarge
        case .terminated: throw RMError.cancelled
        @unknown default: throw RMError.cancelled
        }
    }
    private func consume(_ id: UUID, input: RunRequest, context: ScopedToolContext) async {
        let lease = epoch
        do {
            try Task.checkCancellation(); guard sessions[context.conversationID] != nil else { throw RMError.cancelled }
            for try await event in await runs.stream(input,context:context) {
                try Task.checkCancellation()
                guard var snapshot = snapshots[id],lease == epoch else { return }
                let valid = await auth.clients().contains { $0.id == snapshot.owner && !$0.revoked }
                guard lease == epoch,valid,!deniedClients.contains(snapshot.owner) else { throw RMError.cancelled }
                switch event {
                case .text(let t): snapshot.text += t; record(id,.object(["type":"text","text":.string(t)]))
                case .reasoning(let t): snapshot.reasoning += t; record(id,.object(["type":"reasoning","text":.string(t)]))
                case .result(let r): snapshot.tools.removeAll { $0.id == r.id }; snapshot.tools.append(r); record(id,(try? encoded(r)) ?? .null)
                case .usage(let u): snapshot.usage = u
                case .finish(let reason): snapshot.state = reason == "approval" ? "approval" : reason == "cancelled" ? "cancelled" : "completed"
                default: break
                }
                guard snapshot.text.utf8.count + snapshot.reasoning.utf8.count <= 1024*1024, snapshot.tools.reduce(0,{ $0+$1.detail.utf8.count }) <= 512*1024, (eventBytes[id] ?? 0) <= 1024*1024, (events[id]?.count ?? 0) < 10000 else { throw RMError.tooLarge }
                snapshots[id] = snapshot
            }
            if snapshots[id]?.state == "running" { snapshots[id]?.state = "completed" }
        } catch {
            if snapshots[id]?.state != "cancelled" { snapshots[id]?.state = Task.isCancelled || error is CancellationError || (error as? RMError) == .cancelled ? "cancelled" : "failed" }
            snapshots[id]?.error = (error as? RMError ?? .connection).rawValue
            await runs.cancel(context.conversationID)
        }
        guard lease == epoch,snapshots[id] != nil else { return }
        runTasks[id] = nil; record(id,.object(["type":"done","state":.string(snapshots[id]?.state ?? "failed")]))
    }
    private func record(_ id:UUID,_ event:JSON) {
        let count = event.encoded.count
        if count <= 512*1024,(eventBytes[id] ?? 0)+count <= 1024*1024,(events[id]?.count ?? 0) < 9999 {
            events[id,default:[]].append(event); eventBytes[id,default:0] += count
        } else if event["type"].string == "done" { events[id,default:[]].append(event) }
        else { eventBytes[id] = 1024*1024+1 }
    }
    private func eventStream(_ id: UUID, grantID: UUID) -> AsyncThrowingStream<Data,Error> {
        let lease = epoch
        return AsyncThrowingStream(bufferingPolicy:.bufferingOldest(32)) { c in
            let task = Task {
                var index = 0
                while !Task.isCancelled {
                    do {
                        let credential = await self.auth.clients().first { $0.id == grantID && !$0.revoked }
                        guard credential != nil,self.epoch == lease,!self.deniedClients.contains(grantID) else { throw RMError.authentication }
                        let all = self.events[id] ?? []
                        for row in all.dropFirst(index) { try Self.yield(Compatibility.frame(row),to:c) }; index = all.count
                        if self.runTasks[id] == nil { c.finish(); return }
                        try await Task.sleep(for:.milliseconds(200))
                    } catch { c.finish(throwing:error); return }
                }
                c.finish()
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
    private func encoded<T:Encodable>(_ value: T) throws -> JSON { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970; return try JSON.parse(encoder.encode(value)) }
}
