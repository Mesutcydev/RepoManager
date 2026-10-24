import SwiftUI
import RepoManagerCore
import RepoManagerUI
import UserNotifications

extension AppModel {
    func sessionState(_ id: UUID) -> SessionDeviceState { data.sessionStates?[id] ?? SessionDeviceState() }

    func updateSessionState(_ id: UUID, _ change: (inout SessionDeviceState) -> Void) {
        var states = data.sessionStates ?? [:]
        var state = states[id] ?? SessionDeviceState(); change(&state); states[id] = state
        data.sessionStates = states; save()
    }

    func prepareSession(_ id: UUID) {
        guard let chat = data.conversations.first(where: { $0.id == id }) else { return }
        if recaps[id] == nil { recaps[id] = SessionRecap.unseen(in: chat, state: sessionState(id)) }
        updateSessionState(id) { $0.unread = false }
        if !sessionState(id).visited { rememberSession(id) }
    }

    func rememberSession(_ id: UUID) {
        guard let chat = data.conversations.first(where: { $0.id == id }) else { return }
        recaps[id] = nil
        let seen = chat.followsLatest ? chat.messages.last : chat.messages.first(where: { $0.id == chat.readingMessageID })
        updateSessionState(id) { state in
            state.visited = true
            // Do not move a read cursor backwards when revisiting older text.
            let oldIndex = chat.messages.firstIndex(where: { $0.id == state.seenMessageID }) ?? -1
            let newIndex = chat.messages.firstIndex(where: { $0.id == seen?.id }) ?? -1
            if newIndex >= oldIndex { state.seenMessageID = seen?.id; state.seenSignature = seen.map(SessionContext.signature) }
        }
    }

    func dismissRecap(_ id: UUID) { recaps[id] = nil; rememberSession(id) }

    func markUnread(_ id: UUID) {
        rememberSession(id); updateSessionState(id) { $0.unread = true }; selection = .chats
    }

    func compactSession(_ id: UUID) {
        guard !running.contains(id), !stopping.contains(id),
              let index = data.conversations.firstIndex(where: { $0.id == id }),
              let checkpoint = SessionContext.checkpoint(data.conversations[index]) else { return }
        data.conversations[index].contextCheckpoint = checkpoint
        data.conversations[index].contextNotice = String(localized: "Earlier context was compacted locally. The full conversation remains available; the next reply uses recent turns and bounded excerpts.")
        data.conversations[index].modified = Date(); save()
    }

    func selectReasoning(_ preference: ReasoningPreference) {
        editConversation { $0.reasoningPreference = preference }
    }

    func setCompletionNotifications(_ enabled: Bool, for id: UUID) async {
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else {
                    error = String(localized: "Notifications are disabled for Repo Manager. Enable them in Settings to receive completion alerts."); return
                }
            } catch { self.error = String(localized: "Could not enable completion notifications. Try again in Settings."); return }
        }
        guard !locked, data.conversations.contains(where: { $0.id == id }) else { return }
        updateSessionState(id) { $0.alwaysNotify = enabled }
    }

    func notifyCompletion(_ id: UUID, responseID: UUID) async {
        let state = sessionState(id)
        guard state.receivesCompletion else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Reply finished")
        content.body = String(localized: "Open Repo Manager to view the conversation.")
        content.sound = .default
        content.userInfo = ["conversationID": id.uuidString]
        let request = UNNotificationRequest(identifier: "session.\(id).\(responseID)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Notification content contains no repository paths, prompts or reply text.
@MainActor final class SessionNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SessionNotificationRouter()
    var openSession: ((UUID) -> Void)?
    func register() { UNUserNotificationCenter.current().delegate = self }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let text = response.notification.request.content.userInfo["conversationID"] as? String, let id = UUID(uuidString: text) else { return }
        await MainActor.run { self.openSession?(id) }
    }
}

struct SessionIdentityButton: View {
    let title: String
    let workspace: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                Text(workspace).font(.caption).foregroundStyle(RMPalette.secondary).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            }
            .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            .padding(.horizontal, RMLayout.cardInset).padding(.vertical, RMLayout.elementGap)
            .frame(minHeight: RMLayout.minimumHit)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 280)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(RMPressButtonStyle())
        .foregroundStyle(RMPalette.text)
        .accessibilityLabel(String(localized: "Session details, \(title), \(workspace)"))
        .accessibilityIdentifier("chat.session")
    }
}

struct SessionRecapView: View {
    let recap: SessionRecap
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: RMLayout.elementGap) {
            VStack(alignment: .leading, spacing: RMLayout.unit) {
                Text("Since you left").font(RMType.label)
                Text("\(recap.replies) updated replies · \(recap.tools) tool calls").font(RMType.meta)
                if recap.stopped { Text("Work stopped when the app left the foreground. Continue from the retained response when ready.").font(RMType.meta) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.subheadline)
                    .frame(width: RMLayout.minimumHit, height: RMLayout.minimumHit).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Dismiss recap")
                .accessibilityIdentifier("chat.recap.dismiss")
        }
        .foregroundStyle(RMPalette.secondary).padding(RMLayout.rowGap)
        .background { RMFrostedPanelBackground(cornerRadius: RMLayout.rowCorner) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.recap")
    }
}
