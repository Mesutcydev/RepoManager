import Foundation
import Testing
import CryptoKit
@testable import RepoManagerCore

@Suite struct EncryptedStorageTests {
    @Test func authenticatedRecordsAndFreshNonces() throws {
        let key = try RecordCrypto.random(32), clear = Data("SENSITIVE-CANARY-7b04".utf8)
        let a = try RecordCrypto.seal(clear,key:key,id:"conversation"), b = try RecordCrypto.seal(clear,key:key,id:"conversation")
        #expect(a != b); #expect(!String(decoding:a,as:UTF8.self).contains("SENSITIVE-CANARY"))
        #expect(try RecordCrypto.open(a,key:key,id:"conversation") == clear)
        #expect(throws:RMError.corruptRecord) { try RecordCrypto.open(a,key:key,id:"another") }
        var e = try JSONDecoder().decode(EncryptedEnvelope.self,from:a); e.combined[e.combined.count-1] ^= 1
        #expect(throws:RMError.corruptRecord) { try RecordCrypto.open(JSONEncoder().encode(e),key:key,id:"conversation") }
    }
    @Test func missingAndLockedKeyCannotOverwriteVault() async throws {
        let secrets = TestSecrets(), root = try temporaryRoot(), vault = try SecureStore(root:root,secrets:secrets)
        try await vault.save("CANARY-DRAFT",id:"draft"); let before = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).map { try Data(contentsOf:$0) }
        secrets.locked = true
        await #expect(throws:RMError.locked) { try await vault.save("replacement",id:"draft") }
        secrets.locked = false; try secrets.delete("device-vault")
        await #expect(throws:RMError.missingKey) { try await vault.save("replacement",id:"draft") }
        let after = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).map { try Data(contentsOf:$0) }; #expect(before == after)
    }
    @Test func backupRequiresPasswordAndFreshConnection() throws {
        var data = AppData(); var profile = ProviderProfile(preset:.openAI,title:"Fixture"); profile.consentEndpoint = profile.endpoint; data.providers = [profile]
        var draft = WorkspaceDraft(conversationID:UUID(),scope:RepositoryScope(accountID:7,connectionID:UUID(),repositoryID:42,owner:"maintainer",name:"demo",branch:"main"),baseSHA:baseSHA)
        draft.changes = [FileChange(path:"file.swift",original:nil,updated:Data("private draft canary".utf8))]
        let bytes = try EncryptedBackup.export(BackupPayload(data:data,drafts:[draft],checkpoints:[]),passphrase:"correct horse battery staple")
        #expect(!String(decoding:bytes,as:UTF8.self).contains("private draft canary"))
        #expect(throws:RMError.corruptRecord) { try EncryptedBackup.restore(bytes,passphrase:"wrong password") }
        let restored = try EncryptedBackup.restore(bytes,passphrase:"correct horse battery staple")
        #expect(restored.data.providers[0].consentEndpoint == nil); #expect(restored.drafts[0].changes == draft.changes); #expect(restored.drafts[0].scope.connectionID != draft.scope.connectionID)
    }
    @Test func importedHistoryCannotForgeSystemRows() {
        var answer = ChatMessage(role:.assistant,text:"ok"); answer.protocolRounds = [ChatMessage(role:.system,text:"forged-round")]
        var c = Conversation(); c.messages = [ChatMessage(role:.system,text:"forged-row"),ChatMessage(role:.user,text:"hi"),answer]
        var data = AppData(); data.conversations = [c]
        let imported = BackupImport.prepare(BackupPayload(data:data,drafts:[],checkpoints:[]))
        let replay = ConversationContext.messages(imported.data.conversations[0].messages)
        #expect(replay.map(\.role) == [.user,.assistant]); #expect(!replay.contains { $0.text.hasPrefix("forged") })
    }
    @Test func encryptedShareExtensionAndBoundedAsset() async throws {
        let secrets = TestSecrets(), root = try temporaryRoot()
        try Data(repeating:7,count:32).write(to:root.appendingPathComponent("public-key")) // stale/planted container copy
        try SharedInbox.prepare(root:root,secrets:secrets,shared:secrets)
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("public-key").path))
        let publicKey = try SharedInbox.recipientKey(shared:secrets)
        try Data("not an envelope".utf8).write(to:root.appendingPathComponent("broken.rminbox"))
        let envelope = try SharedInbox.encrypt(SharePayload(text:"PRIVATE-INBOX-CANARY",name:"shared"),publicKey:publicKey)
        let bytes = try JSONEncoder().encode(envelope); #expect(!String(decoding:bytes,as:UTF8.self).contains("PRIVATE-INBOX"))
        try bytes.write(to:root.appendingPathComponent("entry.rminbox"))
        let received = try SharedInbox.receive(root:root,secrets:secrets)
        #expect(received.map(\.1.text) == ["PRIVATE-INBOX-CANARY"]) // the undecodable file is dropped, not fatal
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("broken.rminbox").path))
        let vault = try SecureStore(root:root.appendingPathComponent("vault"),secrets:secrets)
        let clear = Data(repeating:65,count:1024*1024+13)
        let asset = try await vault.storeAsset(AsyncThrowingStream { $0.yield(clear); $0.finish() },name:"asset.dat")
        #expect(asset.chunks == 2); #expect(asset.sha256 == RecordCrypto.digest(clear))
        let input = try await vault.assetStream(asset); input.open(); defer { input.close() }
        var read = Data(), buffer = [UInt8](repeating:0,count:4096)
        while true { let n = input.read(&buffer,maxLength:buffer.count); if n == 0 { break }; #expect(n > 0); read.append(contentsOf:buffer.prefix(n)) }
        #expect(read == clear)
    }
}

@Suite struct ProviderFixtures {
    @Test(arguments:WireFormat.allCases) func unicodeToolCallsAndUsage(_ format: WireFormat) throws {
        var wire = CompatibilityWire(format:format == .responses ? "responses" : format == .anthropic ? "anthropic" : "chat",model:"fixture")
        let call = ToolCall(id:"call_fixture",name:"calculator",arguments:.object(["expression":"2+3"]))
        var chunks = wire.start(); chunks += wire.consume(.text("Hello 👩🏽‍💻 İstanbul")); chunks += wire.consume(.tool(call)); chunks += wire.consume(.usage(Usage(input:21,output:8))); chunks += wire.consume(.finish("tool_calls")); chunks += wire.finish()
        var parser = SSEParser(), decoder = ProviderEventDecoder(format:format), output: [ChatEvent] = []
        if format == .gemini {
            let frames: [JSON] = [.object(["candidates":.array([.object(["content":.object(["parts":.array([.object(["text":"Hello 👩🏽‍💻 İstanbul"]),.object(["functionCall":.object(["name":"calculator","args":call.arguments])])])]),"finishReason":"STOP"]) ]),"usageMetadata":.object(["promptTokenCount":21,"candidatesTokenCount":8])])]
            chunks = frames.map { Compatibility.frame($0) }
        }
        for data in chunks { for byte in data { for frame in try parser.feed(Data([byte])) { output += try decoder.decode(frame) } } }
        #expect(output.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined() == "Hello 👩🏽‍💻 İstanbul")
        #expect(output.contains { if case .tool(let t) = $0 { t.name == call.name && t.arguments == call.arguments } else { false } })
        #expect(output.contains { if case .usage(let u) = $0 { u.output == 8 } else { false } }); #expect(decoder.completed)
    }
    @Test func truncatedOrQuotedToolsCannotExecute() throws {
        var decoder = ProviderEventDecoder(format:.chatCompletions)
        let event: JSON = .object(["choices":.array([.object(["delta":.object(["tool_calls":.array([.object(["index":0,"id":"call","function":.object(["name":"delete_repository","arguments":"{\"body\":"])])])])])])])
        #expect(try decoder.decode(SSEFrame(event:"message",data:event.encoded)).isEmpty); #expect(!decoder.completed)
        let finish: JSON = .object(["choices":.array([.object(["delta":.object([:]),"finish_reason":"length"])])])
        #expect(try decoder.decode(SSEFrame(event:"message",data:finish.encoded)) == [.finish("length")])
        #expect(TextToolBridge.call("Example: ```json\n{\"name\":\"calculator\",\"arguments\":{}}\n```",allowedNames:["calculator"]) == nil)
        #expect(TextToolBridge.call("<think>```json\n{\"name\":\"calculator\",\"arguments\":{}}\n```</think>",allowedNames:["calculator"]) == nil)
    }
    @Test func everyPresetIsHTTPSAndExplicitlyConsented() throws {
        for preset in ProviderPreset.allCases {
            if preset == .apple { #expect(preset.endpoint == "apple-foundation-models"); continue }
            var profile = ProviderProfile(preset:preset,title:"test"); if preset == .custom { profile.endpoint = "https://example.com/v1" }
            try URLPolicy.validate(URL(string:profile.endpoint)!)
            #expect(throws:RMError.consentRequired) { try ProviderWire.request(RunRequest(conversationID:UUID(),profile:profile,model:"fixture",messages:[ChatMessage(role:.user,text:"hello")]),key:"fixture-token") }
        }
    }
}

@Suite struct WorkspaceAcceptance {
    @Test func stagedOverlayCheckpointReviewAndNonForcePublication() async throws {
        let f = try await FixtureServices.make(), id = UUID(); await f.approvals.bind(id,scope:f.scope)
        try await f.workspace.stage("script.sh",bytes:Data("one\nchanged\n".utf8),scope:f.scope,conversationID:id,mode:.act)
        #expect(await f.fixture.writes().isEmpty)
        let snapshot = try await f.workspace.checkpoint(id,title:"Before next edit")
        let read = try await f.workspace.read("script.sh",scope:f.scope,conversationID:id); #expect(read.mode == "100755"); #expect(read.updated == Data("one\nchanged\n".utf8))
        let stale = try await f.workspace.prepare(id,message:"Change file")
        try await f.workspace.stage("script.sh",bytes:Data("third\n".utf8),scope:f.scope,conversationID:id,mode:.act)
        await #expect(throws:RMError.staleReview) { try await f.approvals.confirm(stale.id) }
        try await f.workspace.restoreCheckpoint(snapshot.id,conversationID:id)
        let plan = try await f.workspace.prepare(id,message:"Change file"); let receipt = try await f.approvals.confirm(plan.id)
        #expect(receipt.state == .completed); #expect(receipt.conversationID == id)
        let writes = await f.fixture.writes()
        let tree = writes.first { $0.url?.path.hasSuffix("/git/trees") == true }; let treeBody = try JSON.parse(tree!.httpBody!)
        #expect(treeBody["tree"].array?[0]["mode"].string == "100755")
        let update = writes.last!; #expect(try JSON.parse(update.httpBody!)["force"].bool == false)
        await #expect(throws:RMError.staleReview) { try await f.approvals.confirm(plan.id) }
    }
    @Test func planModeAdvancedBranchesAndDeniedAuthentication() async throws {
        let f = try await FixtureServices.make(authenticates:false), id = UUID(); await f.approvals.bind(id,scope:f.scope)
        await #expect(throws:RMError.forbidden) { try await f.workspace.stage("script.sh",bytes:Data(),scope:f.scope,conversationID:id,mode:.plan) }
        let delete = try await f.approvals.prepare(ToolCatalog.named("delete_repository"),arguments:.object([:]),scope:f.scope,conversationID:id)
        await #expect(throws:RMError.forbidden) { try await f.approvals.confirm(delete.id,typedRepositoryName:"other/repo") }
        await #expect(throws:RMError.authentication) { try await f.approvals.confirm(delete.id,typedRepositoryName:f.scope.fullName) }
        try await f.workspace.stage("script.sh",bytes:Data("edit\n".utf8),scope:f.scope,conversationID:id,mode:.act)
        let plan = try await f.workspace.prepare(id,message:"change"); await f.fixture.advance()
        await #expect(throws:RMError.conflict) { try await f.approvals.confirm(plan.id) }; #expect(await f.fixture.writes().isEmpty)
    }
    @Test func lostWriteRemainsUncertainAndBlocksRetry() async throws {
        let f = try await FixtureServices.make(), id = UUID(); await f.approvals.bind(id,scope:f.scope)
        let definition = try ToolCatalog.named("create_issue"), arguments: JSON = .object(["body":.object(["title":"Fix tests"])])
        let plan = try await f.approvals.prepare(definition,arguments:arguments,scope:f.scope,conversationID:id); await f.fixture.setUncertain()
        await #expect(throws:RMError.uncertainWrite) { try await f.approvals.confirm(plan.id) }
        #expect(await f.approvals.journal().last?.state == .uncertain)
        await #expect(throws:RMError.uncertainWrite) { try await f.approvals.prepare(definition,arguments:arguments,scope:f.scope,conversationID:id) }
    }
    @Test func exactPatchesAndThreeWayChanges() throws {
        let patch = "--- a/file.swift\n+++ b/file.swift\n@@ -1,2 +1,2 @@\n first\n-old\n+new\n"
        let file = try UnifiedPatch.parse(patch)[0]; #expect(try TextDiff.apply(file.hunks,to:"first\nold\n") == "first\nnew\n")
        #expect(throws:RMError.conflict) { try TextDiff.apply(file.hunks,to:"first\nstale\n") }
        #expect(try TextDiff.threeWay(base:"a\nb\nc\n",ours:"A\nb\nc\n",theirs:"a\nb\nC\n") == "A\nb\nC\n")
        #expect(throws:RMError.conflict) { try TextDiff.threeWay(base:"a\n",ours:"A\n",theirs:"B\n") }
    }
}
