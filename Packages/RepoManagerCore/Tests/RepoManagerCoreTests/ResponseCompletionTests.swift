import Foundation
import Testing
@testable import RepoManagerCore

private let completedText = "Audit findings: İstanbul 👩🏽‍💻 stays readable."
private func completedMessage(_ text:String,phase:String = "final_answer",id:String = "msg_snapshot") -> JSON {
    .object(["type":"message","id":.string(id),"role":"assistant","status":"completed","phase":.string(phase),
             "content":.array([.object(["type":"output_text","text":.string(text),"annotations":.array([])])])])
}
private func completionFrame(_ root:JSON) -> SSEFrame { SSEFrame(event:"message",data:root.encoded) }
private func terminal(_ items:[JSON]) -> JSON { .object(["type":"response.completed","response":.object(["output":.array(items),"usage":.object(["input_tokens":904,"output_tokens":16])])]) }

@Suite struct ResponseCompletionTests {
    @Test(arguments:[0,1,2,3,4]) func completedTextIsRecoveredExactlyOnce(_ shape:Int) throws {
        let item = completedMessage(completedText)
        var frames:[JSON] = []
        if shape == 4 { frames.append(.object(["type":"response.output_text.delta","output_index":0,"content_index":0,"item_id":"msg_snapshot","delta":"Audit findings: "])) }
        if shape == 1 || shape == 4 { frames.append(.object(["type":"response.output_text.done","output_index":0,"content_index":0,"item_id":"msg_snapshot","text":.string(completedText)])) }
        if shape == 2 { frames.append(.object(["type":"response.content_part.done","output_index":0,"content_index":0,"item_id":"msg_snapshot","part":try #require(item["content"].array?.first)])) }
        if shape == 3 || shape == 4 { frames.append(.object(["type":"response.output_item.done","output_index":0,"item":item])) }
        frames.append(terminal([item]))
        var decoder = ProviderEventDecoder(format:.responses),text = ""
        for frame in frames { for event in try decoder.decode(completionFrame(frame)) { if case .text(let value) = event { text += value } } }
        #expect(text == completedText)
    }

    @Test func terminalMetadataDoesNotEraseFinishedToolItems() throws {
        let call:JSON = .object(["type":"function_call","id":"fc_read","call_id":"call_read","name":"read_file","arguments":"{\"path\":\"script.sh\"}","status":"completed"])
        var decoder = ProviderEventDecoder(format:.responses)
        _ = try decoder.decode(completionFrame(.object(["type":"response.output_item.done","output_index":0,"item":call])))
        let events = try decoder.decode(completionFrame(terminal([])))
        #expect(events.contains { if case .tool(let value) = $0 { value.id == "call_read" && value.name == "read_file" } else { false } })
    }

    @Test func finishedArgumentsStillProduceACallAtCompletion() throws {
        var decoder = ProviderEventDecoder(format:.responses)
        _ = try decoder.decode(completionFrame(.object(["type":"response.output_item.added","output_index":0,"item":.object(["type":"function_call","id":"fc_read","call_id":"call_read","name":"read_file","arguments":""])])))
        _ = try decoder.decode(completionFrame(.object(["type":"response.function_call_arguments.done","item_id":"fc_read","output_index":0,"arguments":"{\"path\":\"script.sh\"}"])))
        let events = try decoder.decode(completionFrame(terminal([])))
        #expect(events.contains { if case .tool(let value) = $0 { value.id == "call_read" && value.arguments["path"].string == "script.sh" } else { false } })
    }

    @Test func completedSummariesAndRefusalsAreVisible() throws {
        var decoder = ProviderEventDecoder(format:.responses)
        let items:[JSON] = [.object(["type":"reasoning","id":"rs_summary","encrypted_content":"synthetic-opaque","summary":.array([.object(["type":"summary_text","text":"Checking repository evidence."])])]),
                            .object(["type":"message","id":"msg_refusal","role":"assistant","content":.array([.object(["type":"refusal","refusal":"I cannot complete that request."])])])]
        let events = try decoder.decode(completionFrame(terminal(items)))
        #expect(events.contains(.reasoning("Checking repository evidence.")))
        #expect(events.contains(.text("I cannot complete that request.")))
    }

    @Test func repositoryAuditContinuesBeyondItsPreamble() async throws {
        let services = try await FixtureServices.make(),provider = CompletedAuditProvider()
        let runner = RunCoordinator(provider:provider,tools:services.tools,approvals:services.approvals)
        var profile = ProviderProfile(preset:.openAI,title:"Completed Responses fixture"); profile.models = [ModelMetadata(id:"gpt-6.1-sol")]
        let request = RunRequest(conversationID:UUID(),profile:profile,model:"gpt-6.1-sol",messages:[.init(role:.user,text:"Audit repo for cleanup and better display")])
        var events:[ChatEvent] = []
        for try await event in await runner.stream(request,context:ScopedToolContext(conversationID:request.conversationID,repository:services.scope,mode:.plan)) { events.append(event) }
        #expect(await provider.count() == 2)
        #expect(events.contains { if case .result(let value) = $0 { value.name == "read_file" && value.status == .success } else { false } })
        #expect(events.contains(.text(completedText)))
        #expect(events.filter { if case .finish = $0 { true } else { false } } == [.finish("stop")])
        #expect(await services.fixture.writes().isEmpty)
    }

    @Test func emptySuccessfulResponseIsNotAccepted() async throws {
        let services = try await FixtureServices.make()
        let runner = RunCoordinator(provider:EventProvider(events:[.usage(Usage(input:904,output:16)),.finish("stop")]),tools:services.tools,approvals:services.approvals)
        let request = RunRequest(conversationID:UUID(),profile:ProviderProfile(preset:.openAI,title:"Empty fixture"),model:"fixture",messages:[.init(role:.user,text:"Proceed")])
        var finished = false,failure:Error?
        do { for try await event in await runner.stream(request,context:ScopedToolContext(conversationID:request.conversationID,repository:services.scope,mode:.plan)) { if case .finish = event { finished = true } } }
        catch { failure = error }
        #expect(failure != nil)
        #expect(!finished)
    }
}

private actor CompletedAuditProvider:ProviderClient {
    private var requests = 0
    func count() -> Int { requests }
    nonisolated func stream(_ request:RunRequest) -> AsyncThrowingStream<ChatEvent,Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do { for event in try await self.events(request) { output.yield(event) }; output.finish() }
                catch { output.finish(throwing:error) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
    private func events(_ request:RunRequest) throws -> [ChatEvent] {
        let body = try ProviderWire.body(request),input = body["input"].array ?? []
        defer { requests += 1 }
        var decoder = ProviderEventDecoder(format:.responses)
        switch requests {
        case 0:
            let text = "I’ll review the repository for cleanup opportunities and UI/display improvements."
            let call:JSON = .object(["type":"function_call","id":"fc_audit","call_id":"call_audit","name":"read_file","arguments":"{\"path\":\"script.sh\"}","status":"completed"])
            let frames:[JSON] = [.object(["type":"response.output_text.delta","output_index":0,"delta":.string(text)]),
                                 .object(["type":"response.output_item.done","output_index":0,"item":completedMessage(text,phase:"commentary",id:"msg_preamble")]),
                                 .object(["type":"response.output_item.done","output_index":1,"item":call]),terminal([])]
            return try frames.flatMap { try decoder.decode(completionFrame($0)) }
        case 1:
            guard input.contains(where:{ $0["id"].string == "msg_preamble" && $0["phase"].string == "commentary" }) else { throw RMError.invalidInput }
            guard input.contains(where:{ $0["type"].string == "function_call_output" && $0["call_id"].string == "call_audit" && $0["output"].string?.contains("one\ntwo") == true }) else { throw RMError.invalidInput }
            return try decoder.decode(completionFrame(terminal([completedMessage(completedText)])))
        default: throw RMError.unavailable
        }
    }

    @Test func truncationAndFailureReachTheWireConsistently() throws {
        var decoder = ProviderEventDecoder(format:.anthropic)
        let events = try decoder.decode(completionFrame(.object(["type":"message_delta","delta":.object(["stop_reason":"max_tokens"]),"usage":.object(["output_tokens":4])])))
        #expect(events.contains(.finish("length")))
        var wire = CompatibilityWire(format:"responses",model:"fixture"); _ = wire.start(); _ = wire.consume(.text("partial"))
        for event in events { _ = wire.consume(event) }
        #expect(wire.completed()["status"].string == "incomplete")
        #expect(String(decoding:wire.finish().last ?? Data(),as:UTF8.self).contains("response.incomplete"))
        var chat = CompatibilityWire(format:"chat",model:"fixture"); _ = chat.start()
        #expect(String(decoding:chat.failure(.connection),as:UTF8.self).contains("\"error\""))
    }
}
