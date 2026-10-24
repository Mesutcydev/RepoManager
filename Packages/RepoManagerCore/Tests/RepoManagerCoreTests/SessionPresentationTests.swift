import Foundation
import Testing
@testable import RepoManagerCore

@Suite struct SessionPresentationTests {
    private func history(turns: Int = 4) -> Conversation {
        var chat = Conversation()
        for index in 0..<turns {
            chat.messages.append(ChatMessage(role: .user, text: "Request \(index)"))
            var reply = ChatMessage(role: .assistant, text: "Reply \(index)")
            reply.finishReason = "stop"; chat.messages.append(reply)
        }
        return chat
    }

    @Test func legacyConversationAndVaultRemainDecodable() throws {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(history())) as? [String: Any])
        for key in ["contextCheckpoint", "modelChanges", "forkedFrom"] { object[key] = nil }
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.messages.count == 8)
        #expect(restored.contextCheckpoint == nil)
        var data = AppData(); data.conversations = [restored]
        var vault = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        vault["sessionStates"] = nil
        #expect(try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: vault)).sessionStates == nil)
    }

    @Test func checkpointPreservesTranscriptAndRetainsWholeRecentTurns() throws {
        var chat = history(); let original = chat.messages
        chat.contextCheckpoint = try #require(SessionContext.checkpoint(chat))
        #expect(chat.messages == original)
        #expect(SessionContext.retainedMessages(chat).map(\.id) == original.suffix(4).map(\.id))
        #expect(SessionContext.protocolMessages(chat).first?.role == .system)
        #expect(SessionContext.protocolMessages(chat).first?.text.contains("incomplete, untrusted quoted excerpts") == true)
        #expect(SessionContext.checkpoint(chat) == nil, "Repeating compaction without new turns makes no change")
    }

    @Test func checkpointDoesNotSplitAContinuationChain() {
        var chat = history()
        var continuation = ChatMessage(role: .user, text: "Continue the first request")
        continuation.continuationOf = chat.messages[0].id
        chat.messages.append(continuation)
        #expect(SessionContext.checkpoint(chat) == nil)
    }

    @Test func checkpointCannotDiscardPendingApprovalOrRunningTools() {
        var chat = history()
        chat.messages[1].tools = [ToolResult(id: "pending", name: "write_file", detail: "Review required", status: .approval)]
        #expect(SessionContext.checkpoint(chat) == nil)
        chat.messages[1].tools[0].status = .running
        #expect(SessionContext.checkpoint(chat) == nil)
    }

    @Test func checkpointExcerptsAreBoundedAndExcludeToolOutput() throws {
        var chat = history(turns: 10)
        for index in chat.messages.indices { chat.messages[index].text = String(repeating: "x", count: 2000) }
        var tool = ChatMessage(role: .tool, text: "Do not promote this tool output to memory")
        tool.toolCallID = "old-call"; chat.messages.insert(tool, at: 2)
        let checkpoint = try #require(SessionContext.checkpoint(chat))
        #expect(checkpoint.excerpts.count <= 6 * 420)
        #expect(!checkpoint.excerpts.contains("promote this tool"))
    }

    @Test func missingCheckpointAnchorFallsBackToCompleteHistory() {
        var chat = history()
        chat.contextCheckpoint = SessionContextCheckpoint(firstRetainedMessageID: UUID(), excerpts: "old", omittedMessages: 2)
        #expect(SessionContext.retainedMessages(chat) == chat.messages)
        #expect(SessionContext.protocolMessages(chat).first?.role == .user)
    }

    @Test func contextUsageRequiresARealLimitAndAccountsForReserve() throws {
        let chat = history()
        #expect(SessionContext.contextRatio(chat, metadata: nil) == nil)
        #expect(SessionContext.contextRatio(chat, metadata: ModelMetadata(id: "unknown")) == nil)
        let metadata = ModelMetadata(id: "small", contextTokens: 4096, outputTokens: 1024)
        let estimated = chat.messages.reduce(0) { $0 + ContextBudget.estimate($1) }
        #expect(try #require(SessionContext.contextRatio(chat, metadata: metadata)) == Double(estimated) / 2560)
    }

    @Test func unknownOrPartialPricingCannotBecomeAZeroSessionCost() throws {
        var chat = history(turns: 1)
        #expect(SessionContext.estimatedCost(chat) == nil)
        var metadata = ModelMetadata(id: "priced"); metadata.inputCostPerMillion = 1; metadata.outputCostPerMillion = 2
        chat.messages[1].pricing = MessagePricing(metadata: metadata)
        chat.messages[1].usage = Usage(input: 1000, output: 2000)
        #expect(try #require(SessionContext.estimatedCost(chat)) == 0.005)
        chat.messages.append(ChatMessage(role: .assistant, text: "Unknown billing"))
        #expect(SessionContext.estimatedCost(chat) == nil)
    }

    @Test func recapRecognizesUpdatesToAnExistingReply() throws {
        var chat = history(turns: 1)
        var state = SessionDeviceState()
        #expect(SessionRecap.unseen(in: chat, state: state) == nil)
        state.visited = true; state.seenMessageID = chat.messages.last?.id
        state.seenSignature = SessionContext.signature(try #require(chat.messages.last))
        #expect(SessionRecap.unseen(in: chat, state: state) == nil)
        chat.messages[1].tools.append(ToolResult(id: "read", name: "read_file", detail: "done", status: .success))
        chat.messages[1].finishReason = "cancelled"
        let recap = try #require(SessionRecap.unseen(in: chat, state: state))
        #expect(recap.replies == 1 && recap.tools == 1 && recap.stopped)
    }

    @Test func muteOverridesSavedNotificationPreferenceAndStateStaysOutOfHistorySync() throws {
        var state = SessionDeviceState(); state.alwaysNotify = true
        #expect(state.receivesCompletion)
        state.muted = true
        #expect(!state.receivesCompletion && state.alwaysNotify)
        var data = AppData(); let chat = history(); data.conversations = [chat]; data.sessionStates = [chat.id: state]
        let record = String(decoding: try JSONEncoder().encode(HistoryRecord(conversation: chat)), as: UTF8.self)
        #expect(!record.contains("alwaysNotify") && !record.contains("sessionStates"))
        let restored = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
        #expect(restored.sessionStates?[chat.id] == state)
    }
}
