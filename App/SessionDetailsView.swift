import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct SessionDetailsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var route: Route?
    @State private var deleting = false
    @State private var requestingNotifications = false
    private enum Route: String, Identifiable { case models, instructions, export; var id: String { rawValue } }

    var body: some View {
        NavigationStack {
            if let chat = model.conversation {
                ScrollView {
                    VStack(alignment: .leading, spacing: RMLayout.groupGap) {
                        HStack(alignment: .top, spacing: RMLayout.cardInset) {
                            SessionSheetHeading(title: chat.title, workspace: chat.repository.map { "\($0.fullName) · \($0.branch)" } ?? String(localized: "Personal workspace"), running: model.running.contains(chat.id), stopping: model.stopping.contains(chat.id))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Done", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).rmIconButton()
                                .accessibilityIdentifier("chat.session.done")
                        }
                        SessionActionGrid(pinned: chat.pinned, muted: model.sessionState(chat.id).muted,
                            canCompact: !model.running.contains(chat.id) && !model.stopping.contains(chat.id) && SessionContext.checkpoint(chat) != nil,
                            canFork: !model.running.contains(chat.id) && !model.stopping.contains(chat.id),
                            pin: { model.editConversation { $0.pinned.toggle() } },
                            unread: { model.markUnread(chat.id); dismiss() },
                            mute: { model.updateSessionState(chat.id) { $0.muted.toggle() } },
                            compact: { model.compactSession(chat.id) },
                            fork: { model.fork(chat.id); dismiss() },
                            export: { route = .export })
                        SessionConfigurationRows(model: model, chat: chat, chooseModel: { route = .models })
                        SessionNotificationSection(enabled: model.sessionState(chat.id).alwaysNotify,
                            muted: model.sessionState(chat.id).muted, pending: requestingNotifications) { enabled in
                                requestingNotifications = true
                                Task { await model.setCompletionNotifications(enabled, for: chat.id); requestingNotifications = false }
                            }
                        DisclosureGroup("More session options") {
                          VStack(spacing: 0) {
                            Button("Search conversation", systemImage: "magnifyingglass") { model.chatSearchVisible = true; dismiss() }
                                .sessionSheetRow().accessibilityIdentifier("chat.session.search")
                            Divider()
                            Button("Project instructions and memory", systemImage: "slider.horizontal.3") { route = .instructions }
                                .sessionSheetRow()
                            Divider()
                            Picker("Persona", selection: Binding(get: { chat.personaID }, set: { id in model.editConversation { $0.personaID = id } })) {
                                Text("Default assistant").tag(UUID?.none)
                                ForEach(model.data.personas) { Text($0.title).tag(Optional($0.id)) }
                            }.padding(RMLayout.cardInset)
                          }.padding(.top, RMLayout.elementGap)
                        }.font(RMType.detail).padding(RMLayout.cardInset)
                            .background { RMFrostedPanelBackground() }
                        if let checkpoint = chat.contextCheckpoint {
                            DisclosureGroup("Compacted context excerpts") {
                                Text(checkpoint.excerpts).font(RMType.meta).textSelection(.enabled).padding(.top, RMLayout.elementGap)
                                Text("The excerpts are incomplete. The full transcript is preserved.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
                            }.font(RMType.detail)
                        }
                        Button("Delete Session", systemImage: "trash", role: .destructive) { deleting = true }
                            .sessionSheetRow().foregroundStyle(RMPalette.red)
                            .background { RMFrostedPanelBackground() }
                            .accessibilityIdentifier("chat.session.delete")
                    }
                    .padding(RMLayout.pageInset).padding(.top, RMLayout.elementGap).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("chat.session.sheet")
                .toolbar(.hidden, for: .navigationBar)
                .alert("Delete this session?", isPresented: $deleting) {
                    Button("Delete Session", role: .destructive) { dismiss(); Task { await model.deleteChat(chat.id) } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This removes the conversation and local staged workspace, stops any active reply, and records a deletion for enabled history sync. Published GitHub changes remain on GitHub.") }
            }
        }
        .sheet(item: $route) { destination in
            switch destination {
            case .models: ModelPickerView(model: model)
            case .instructions: ConversationDetailsView(model: model)
            case .export: BackupView(model: model, conversationOnly: true)
            }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible).presentationBackground(.thinMaterial)
    }
}

private struct SessionSheetHeading: View {
    let title: String
    let workspace: String
    let running: Bool
    let stopping: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.elementGap) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(RMPalette.text).textSelection(.enabled)
            Text(workspace).font(RMType.detail).foregroundStyle(RMPalette.secondary).textSelection(.enabled)
            if running || stopping { Label(stopping ? String(localized: "Stopping…") : String(localized: "Working"), systemImage: "circle.dotted").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
        }
    }
}

private struct SessionActionGrid: View {
    let pinned: Bool; let muted: Bool; let canCompact: Bool; let canFork: Bool
    let pin: () -> Void; let unread: () -> Void; let mute: () -> Void
    let compact: () -> Void; let fork: () -> Void; let export: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: RMLayout.unit) { actions(compact: true) }
                    .fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 88), spacing: RMLayout.elementGap)], spacing: RMLayout.rowGap) {
                actions(compact: false)
            }
        }
    }
    @ViewBuilder private func actions(compact: Bool) -> some View {
            SessionAction(title: pinned ? String(localized: "Unpin") : String(localized: "Pin"), symbol: pinned ? "pin.slash" : "pin", identifier: "chat.session.pin", compact: compact, action: pin)
            SessionAction(title: String(localized: "Unread"), symbol: "envelope.badge", identifier: "chat.session.unread", compact: compact, action: unread)
            SessionAction(title: muted ? String(localized: "Unmute") : String(localized: "Mute"), symbol: muted ? "bell.slash" : "bell", identifier: "chat.session.mute", compact: compact, action: mute)
            SessionAction(title: String(localized: "Compact"), symbol: "rectangle.compress.vertical", identifier: "chat.session.compact", compact: compact, action: self.compact).disabled(!canCompact).accessibilityLabel("Compact context")
            SessionAction(title: String(localized: "Fork"), symbol: "arrow.triangle.branch", identifier: "chat.session.fork", compact: compact, action: fork).disabled(!canFork)
            SessionAction(title: String(localized: "Export"), symbol: "square.and.arrow.up", identifier: "chat.session.export", compact: compact, action: export)
    }
}

private struct SessionAction: View {
    let title: String; let symbol: String; let identifier: String; let compact: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: RMLayout.elementGap) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(compact ? .caption : RMType.meta).multilineTextAlignment(.center).fixedSize(horizontal: compact, vertical: true)
            }.frame(minWidth: RMLayout.minimumHit, maxWidth: .infinity, minHeight: compact ? 64 : 68).padding(.vertical, RMLayout.elementGap).contentShape(Rectangle())
        }.buttonStyle(RMPressButtonStyle()).foregroundStyle(RMPalette.text).accessibilityIdentifier(identifier)
    }
}

private struct SessionConfigurationRows: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let chat: Conversation
    let chooseModel: () -> Void
    private var metadata: ModelMetadata? { model.data.providers.first(where: { $0.id == chat.providerID })?.models.first(where: { $0.id == chat.modelID }) }
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.elementGap) {
            VStack(spacing: 0) {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))) {
                    Button(action: chooseModel) {
                        LabeledContent {
                            HStack { Text(metadata?.displayName ?? (chat.modelID.isEmpty ? String(localized: "Choose model") : chat.modelID)).multilineTextAlignment(.trailing); Image(systemName: "chevron.right").font(RMType.meta) }
                        } label: { Text("Model").foregroundStyle(RMPalette.secondary) }
                    }.buttonStyle(.plain).sessionSheetRow().accessibilityIdentifier("chat.session.model")
                    ReasoningControl(model: model, conversation: chat, showsLabel: true)
                        .padding(.horizontal, RMLayout.cardInset).padding(.bottom, typeSize.isAccessibilitySize ? RMLayout.elementGap : 0)
                }
                Divider()
                LabeledContent {
                    if let ratio = SessionContext.contextRatio(chat, metadata: metadata) {
                        HStack(spacing: RMLayout.elementGap) {
                            ZStack {
                                Circle().stroke(RMPalette.secondary.opacity(0.2), lineWidth: 2)
                                Circle().trim(from: 0, to: min(1, max(0, ratio))).stroke(RMPalette.text, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                            }.frame(width: 16, height: 16).accessibilityHidden(true)
                            Text("≈\(ratio.formatted(.percent.precision(.fractionLength(0))))").monospacedDigit()
                        }
                    }
                    else { Text("Unavailable").foregroundStyle(RMPalette.secondary) }
                } label: { Text("Context").foregroundStyle(RMPalette.secondary) }
                    .sessionSheetRow().accessibilityIdentifier("chat.session.context")
                Divider()
                LabeledContent {
                    if let cost = SessionContext.estimatedCost(chat) { Text(cost, format: .currency(code: "USD").precision(.fractionLength(2...6))) }
                    else { Text("Unavailable").foregroundStyle(RMPalette.secondary) }
                } label: { Text("Estimated session cost").foregroundStyle(RMPalette.secondary) }
                    .sessionSheetRow()
            }.background { RMFrostedPanelBackground() }
            DisclosureGroup("Context and cost") {
                Text("Context estimates retained messages against this model’s usable input limit. System instructions and tool definitions can add usage. Unknown pricing is never treated as free.").padding(.top, RMLayout.elementGap)
                if model.running.contains(chat.id) { Text("Model and effort changes apply to the next reply.") }
                Text("Compact context keeps recent requests and bounded excerpts without deleting the transcript. It becomes available when there are older turns to reduce.")
            }.font(RMType.meta).foregroundStyle(RMPalette.secondary).padding(.horizontal, RMLayout.unit)
        }
    }
}

private struct SessionNotificationSection: View {
    let enabled: Bool; let muted: Bool; let pending: Bool; let setEnabled: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.elementGap) {
            Toggle("Always Notify", isOn: Binding(get: { enabled }, set: { value in setEnabled(value) }))
                .disabled(muted || pending).sessionSheetRow()
                .background { RMFrostedPanelBackground() }
                .accessibilityIdentifier("chat.session.notify")
            Text(muted ? String(localized: "Unmute this session to receive notifications.") : String(localized: "Notify this device when a local reply finishes. Model runs stop when the app enters the background; remote completion alerts require a session server."))
                .font(RMType.meta).foregroundStyle(RMPalette.secondary)
        }
    }
}

private extension View {
    func sessionSheetRow() -> some View {
        self.font(RMType.body).foregroundStyle(RMPalette.text).padding(.horizontal, RMLayout.cardInset).padding(.vertical, RMLayout.rowGap)
            .frame(maxWidth: .infinity, minHeight: RMLayout.controlLarge, alignment: .leading).contentShape(Rectangle())
    }
}
