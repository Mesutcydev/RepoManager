import Foundation
import Testing
@testable import RepoManagerCore

@Suite struct IntegrationAcceptance {
    @Test func apiOwnershipGrantsNativeApprovalAndProtocols() async throws {
        let f = try await FixtureServices.make()
        var p = ProviderProfile(preset:.openAI); p.models = [ModelMetadata(id:"fixture")]; p.consentEndpoint = p.endpoint
        let provider = EventProvider(events:[.text("Fixture answer 👋"),.tool(ToolCall(id:"client_call",name:"client_task",arguments:.object(["value":1]))),.usage(Usage(input:12,output:4)),.finish("tool_calls")])
        let coordinator = RunCoordinator(provider:provider,tools:f.tools,approvals:f.approvals)
        let auth = APIAuthorization(vault:f.vault,secrets:f.secrets)
        let credential = try await auth.create(APIClientGrant(name:"first",providerIDs:[p.id],repository:f.scope,tools:["read_file","calculator"]))
        let other = try await auth.create(APIClientGrant(name:"second",providerIDs:[p.id],repository:nil,tools:[]))
        let api = AgentAPI(auth:auth,runs:coordinator,tools:f.tools,approvals:f.approvals); await api.configure(profiles:[p])
        func request(_ path: String, _ body: JSON = .object([:]), token: String? = nil, method: String = "POST") -> APIRequest { APIRequest(method:method,path:path,headers:["authorization":"Bearer "+(token ?? credential)],body:body.encoded) }
        #expect(await api.handle(APIRequest(method:"GET",path:"/v1/models",headers:[:])).status == 401)
        let model = "\(p.id)/fixture"
        let created = await api.handle(request("/v1/agent/sessions",.object(["model":.string(model),"mode":"act"]))); #expect(created.status == 201)
        let session = try JSON.parse(created.body)["id"].string!
        let discovered = await api.handle(request("/v1/agent/sessions/\(session)/tools",method:"GET")); let definitions = try JSON.parse(discovered.body).array!
        #expect(Set(definitions.compactMap { $0["name"].string }) == ["read_file","calculator"])
        #expect(await api.handle(request("/v1/agent/sessions/\(session)/tools",token:other,method:"GET")).status == 403)
        let denial = await api.handle(request("/v1/agent/sessions/\(session)/tools/execute",.object(["name":"delete_repository","arguments":.object([:])])))
        #expect(try JSON.parse(denial.body)["status"].string == "failure")
        #expect(await api.handle(request("/v1/agent/sessions/\(session)/approve",.object(["approved":true]))).status == 400)
        for path in ["/v1/chat/completions","/v1/responses","/v1/messages","/api/chat","/api/generate"] {
            var body: [String:JSON] = ["model":.string(model),"stream":true]
            if path == "/v1/responses" { body["input"] = "hello" }
            else if path == "/api/generate" { body["prompt"] = "hello" }
            else { body["messages"] = .array([.object(["role":"user","content":"hello"])]) }
            let result = await api.handle(request(path,.object(body))); #expect(result.status == 200)
            var bytes = Data(); for try await chunk in result.stream! { bytes.append(chunk) }
            #expect(String(decoding:bytes,as:UTF8.self).contains("Fixture answer"))
            if path.hasPrefix("/api/") { #expect(result.contentType == "application/x-ndjson"); for line in String(decoding:bytes,as:UTF8.self).split(separator:"\n") { _ = try JSON.parse(Data(line.utf8)) } }
            else { var parser = SSEParser(); #expect(!(try parser.feed(bytes)).isEmpty) }
        }
        #expect(await f.fixture.writes().isEmpty)
        try await auth.revoke(UUID(uuidString:credential.split(separator:".")[0].description)!)
        #expect(await api.handle(request("/v1/models",method:"GET")).status == 401)
    }
    @Test func clientOwnedToolsRoundTripAcrossFamilies() throws {
        let call = ToolCall(id:"call_1",name:"lookup",arguments:.object(["query":"test"]))
        let chat: JSON = .object(["messages":.array([.object(["role":"user","content":"question"]),.object(["role":"assistant","content":.null,"tool_calls":.array([.object(["id":"call_1","type":"function","function":.object(["name":"lookup","arguments":.string(call.arguments.pretty)])])])]),.object(["role":"tool","tool_call_id":"call_1","content":"result"])])])
        #expect(try Compatibility.messages(chat,format:"chat").last?.calls == [call])
        let responses: JSON = .object(["input":.array([.object(["role":"user","content":"question"]),.object(["type":"function_call","call_id":"call_1","name":"lookup","arguments":.string(call.arguments.pretty)]),.object(["type":"function_call_output","call_id":"call_1","output":"result"])])])
        #expect(try Compatibility.messages(responses,format:"responses").last?.calls == [call])
        let anthropic: JSON = .object(["messages":.array([.object(["role":"user","content":"question"]),.object(["role":"assistant","content":.array([.object(["type":"tool_use","id":"call_1","name":"lookup","input":call.arguments])])]),.object(["role":"user","content":.array([.object(["type":"tool_result","tool_use_id":"call_1","content":"result"])])])])])
        #expect(try Compatibility.messages(anthropic,format:"anthropic").last?.calls == [call])
        #expect(throws:RMError.unsupported) { try Compatibility.messages(.object(["messages":.array([.object(["role":"user","content":.array([.object(["type":"image_url","image_url":"https://example.com/image.png"])])])])]),format:"chat") }
    }
    @Test func oauthPendingDenialExpiryCancellationAndRefreshRotation() async throws {
        let f = try await FixtureServices.make()
        await f.fixture.configureOAuth([.object(["error":"authorization_pending"]),.object(["access_token":"access-fixture","refresh_token":"refresh-fixture","expires_in":1,"refresh_token_expires_in":3600]),.object(["access_token":"access-rotated","refresh_token":"refresh-rotated","expires_in":28800,"refresh_token_expires_in":3600])])
        let flow = try await f.connections.beginDeviceFlow(clientID:"Iv1.fixture")
        let account = try await f.connections.completeDeviceFlow(flow,clientID:"Iv1.fixture")
        let token = try await f.connections.token(accountID:account.id); #expect(token == "access-rotated")
        let stored = try JSON.parse(f.secrets.read("github:7")!); #expect(stored["refresh"].string == "refresh-rotated")
        await #expect(throws:RMError.authentication) { try await f.connections.token(for:f.scope) } // Re-pairing invalidates the old identity.
        let expired = DeviceAuthorization(userCode:"expired",verificationURL:URL(string:"https://github.com/login/device")!,deviceCode:"expired",expires:.distantPast,interval:1)
        await #expect(throws:GitHubPairingError.expired) { try await f.connections.completeDeviceFlow(expired,clientID:"Iv1.fixture") }
        let task = Task { try await f.connections.completeDeviceFlow(flow,clientID:"Iv1.fixture") }; task.cancel()
        await #expect(throws:CancellationError.self) { try await task.value }
        await f.fixture.configureOAuth([.object(["error":"access_denied"])])
        await #expect(throws:GitHubPairingError.denied) { try await f.connections.completeDeviceFlow(flow,clientID:"Iv1.fixture") }
    }
    @Test func historyConflictsTombstonesAndDraftRetention() {
        var local = AppData(), chat = Conversation(); chat.draft = "KEEP LOCAL DRAFT"; chat.messages = [ChatMessage(role:.user,text:"one")]; local.conversations = [chat]
        var remote = chat; remote.messages.append(ChatMessage(role:.assistant,text:"two")); remote.draft = "DO NOT SYNC"
        let merged = HistoryMerge.merge(local:local,remote:[HistoryRecord(conversation:remote)])
        #expect(merged.conversations[0].draft == "KEEP LOCAL DRAFT"); #expect(merged.conversations[0].messages.count == 2)
        remote.messages[0].text = "divergent"; let conflict = HistoryMerge.merge(local:local,remote:[HistoryRecord(conversation:remote)]); #expect(conflict.conversations.count == 2)
        let repeated = HistoryMerge.merge(local:conflict,remote:[HistoryRecord(conversation:remote)])
        #expect(repeated.conversations.count == 2); #expect(repeated.conversations.last?.id == conflict.conversations.last?.id)
        var rename = chat; rename.title = "Renamed on another device"; rename.modified = chat.modified.addingTimeInterval(2)
        #expect(HistoryMerge.merge(local:local,remote:[HistoryRecord(conversation:rename)]).conversations.first?.title == rename.title)
        let deleted = HistoryMerge.merge(local:local,remote:[HistoryRecord(tombstone:chat.id,date:chat.modified.addingTimeInterval(1))]); #expect(deleted.conversations.isEmpty)
        #expect(HistoryMerge.merge(local:deleted,remote:[HistoryRecord(conversation:chat)]).conversations.isEmpty)
    }
    @Test func catalogHasTypedPermissionsAndRemoteReviewRoutes() throws {
        #expect(Set(ToolCatalog.all.map(\.name)).count == ToolCatalog.all.count)
        #expect(ToolCatalog.all.count >= 100)
        for d in ToolCatalog.all {
            #expect(d.schema["type"].string == "object"); #expect(d.schema["additionalProperties"].bool == false)
            #expect(["pull","push","admin"].contains(d.permission))
            if [.mutation,.consequential,.destructive].contains(d.risk) { #expect(d.reviewPath != nil || d.method == "GRAPHQL") }
            if d.nativeOnly { #expect(d.name.contains("secret")); #expect(d.risk == .consequential) }
        }
    }
    @Test func contentReportComposesAMaskedMailtoDraft() throws {
        let token = "ghp_"+String(repeating:"a1",count:18)
        let url = try #require(ContentReport.mailURL(to:"support@example.com",reason:"Harmful or offensive",note:"Tom & Jerry = 2+2?",source:"OpenAI · gpt",messageID:UUID(),created:Date(),response:"Use \(token) "+String(repeating:"x",count:3000)))
        let parts = try #require(URLComponents(url:url,resolvingAgainstBaseURL:false))
        #expect(parts.scheme == "mailto"); #expect(parts.path == "support@example.com")
        let body = try #require(parts.queryItems?.first { $0.name == "body" }?.value)
        #expect(parts.queryItems?.count == 2,"Ampersands in the note must not split the mailto fields")
        #expect(body.contains("Tom & Jerry = 2+2?")); #expect(body.contains("OpenAI · gpt")); #expect(!body.contains(token))
        #expect(body.count < ContentReport.excerptLimit+600)
        #expect(ContentReport.mailURL(to:"",reason:"x",note:"",source:"",messageID:UUID(),created:Date(),response:nil) == nil)
    }
    @Test func everyToolHasAWrittenDescription() {
        #expect(Set(ToolCatalog.about.keys).isSubset(of:Set(ToolCatalog.all.map(\.name))),"No description for a removed tool")
        for d in ToolCatalog.all {
            // A name-only fallback means a new REST tool was added without copy in ToolCatalog.about.
            #expect(d.description != d.name.replacingOccurrences(of:"_",with:" ").capitalized + ".","\(d.name) needs a description")
            #expect(d.description.count <= 120,"\(d.name) description is sent with every request; keep it short")
        }
    }
}
