import SwiftUI
import RepoManagerCore
import RepoManagerUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var query = ""; @State private var archived = false; @State private var renameID: UUID?; @State private var name = ""; @State private var deleting: Conversation?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            List {
                // The top bar owns New chat; the heading owns list options.
                RMPageHeading(String(localized:"Chats")) {
                    Menu {
                        Button("Import encrypted share inbox",systemImage:"square.and.arrow.down") { Task { await model.importInbox() } }
                        Button(archived ? String(localized:"Show current chats") : String(localized:"Show archived chats"),systemImage:"archivebox") { archived.toggle() }
                    } label: { Image(systemName:"ellipsis") }
                        .rmIconButton().accessibilityLabel("Conversation history actions")
                }
                .listRowInsets(EdgeInsets(top:RMLayout.pageInset,leading:RMLayout.pageInset,bottom:RMLayout.groupGap,trailing:RMLayout.pageInset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                Group {
                    if model.data.conversations.isEmpty {
                        VStack(alignment:.leading,spacing:RMLayout.cardInset) {
                            RMEmptyState("What are you working on?",detail:"Connect a provider and begin a conversation. Add a repository when you want to inspect files or plan a change.",symbol:"bubble.left.and.bubble.right")
                            Button("Start a chat",action:model.newChat).rmProminentButton()
                            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:RMLayout.elementGap)) : AnyLayout(HStackLayout(spacing:RMLayout.elementGap))) {
                                Button("Providers") { model.selection = .providers }.rmSecondaryButton()
                                Button("GitHub") { model.selection = .repositories }.rmSecondaryButton()
                            }
                        }.listRowSeparator(.hidden)
                    } else if visible.isEmpty {
                        RMEmptyState(!query.isEmpty ? "No matches" : archived ? "No archived chats" : "No current chats",
                                     detail:!query.isEmpty ? "No conversation matches “\(query)”." : archived ? "Archived conversations appear here." : "Start a chat with the compose button.",
                                     symbol:!query.isEmpty ? "magnifyingglass" : "archivebox")
                            .listRowSeparator(.hidden)
                    } else {
                        Section {
                            ForEach(visible) { chat in
                                Button { model.selectChat(chat.id) } label: { ChatRow(chat:chat,unread:model.sessionState(chat.id).unread) }
                                    .accessibilityIdentifier("history.\(chat.id)")
                                    .listRowSeparatorTint(RMPalette.line)
                                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                                    .contextMenu {
                                        Button(chat.pinned ? String(localized:"Unpin") : String(localized:"Pin"),systemImage:"pin") { mutate(chat.id) { $0.pinned.toggle() } }
                                        Button("Rename",systemImage:"pencil") { name = chat.title; renameID = chat.id }
                                        Button("Fork",systemImage:"arrow.triangle.branch") { model.fork(chat.id) }
                                        Button(chat.archived ? String(localized:"Unarchive") : String(localized:"Archive"),systemImage:"archivebox") { mutate(chat.id) { $0.archived.toggle() } }
                                        Button("Delete",systemImage:"trash",role:.destructive) { deleting = chat }
                                    }
                            }
                        } header: {
                            RMEyebrow(archived ? String(localized:"Archived") : String(localized:"Recent"))
                                .textCase(nil)
                        }
                        .listSectionSeparator(.hidden)
                    }
                }
                .listRowInsets(EdgeInsets(top:0,leading:RMLayout.pageInset,bottom:0,trailing:RMLayout.pageInset))
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .frame(maxWidth:680).frame(maxWidth:.infinity)
            .background(RMPageBackground()).searchable(text:$query,prompt:"Search conversations")
            .toolbar(.hidden,for:.navigationBar).accessibilityIdentifier("history.list")
            .confirmationDialog("Delete “\(deleting?.title ?? "")”?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } }),titleVisibility:.visible,presenting:deleting) { chat in
                Button("Delete conversation",role:.destructive) { Task { await model.deleteChat(chat.id) } }
            } message: { _ in Text("Its messages and local draft are removed from this device. This can’t be undone.") }
            .alert("Rename conversation",isPresented:Binding(get:{ renameID != nil },set:{ if !$0 { renameID = nil } })) {
                TextField("Name",text:$name)
                Button("Save") { if let id = renameID { mutate(id) { $0.title = String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(200)) } }; renameID = nil }
                    .disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Button("Cancel",role:.cancel) { renameID = nil }
            }
        }
    }
    private var visible: [Conversation] {
        model.data.conversations.filter { $0.archived == archived && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.messages.contains(where:{ $0.text.localizedCaseInsensitiveContains(query) })) }
            .sorted { $0.pinned == $1.pinned ? $0.modified > $1.modified : $0.pinned }
    }
    private func mutate(_ id: UUID, _ action: (inout Conversation) -> Void) { guard let i = model.data.conversations.firstIndex(where:{ $0.id == id }) else { return }; action(&model.data.conversations[i]); model.save() }
}
/// Title and time on the first line, the latest message, then scope and draft state.
private struct ChatRow: View {
    let chat: Conversation
    var unread = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment:.leading,spacing:RMLayout.unit) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:RMLayout.unit)) : AnyLayout(HStackLayout(alignment:.firstTextBaseline,spacing:RMLayout.elementGap))) {
                HStack(alignment:.firstTextBaseline,spacing:RMLayout.elementGap) {
                    if unread { Circle().fill(RMPalette.accentText).frame(width:8,height:8).accessibilityLabel("Unread") }
                    if chat.pinned { Image(systemName:"pin.fill").font(RMType.meta).foregroundStyle(RMPalette.secondary).accessibilityLabel("Pinned") }
                    Text(chat.title).font(RMType.rowTitle).foregroundStyle(RMPalette.text)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal:false,vertical:true)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Text(chat.modified,format:.relative(presentation:.named)).font(RMType.meta).foregroundStyle(RMPalette.secondary)
                    .fixedSize(horizontal:true,vertical:false)
            }
            Text(chat.messages.last?.text ?? String(localized:"No messages yet")).font(RMType.detail).foregroundStyle(RMPalette.secondary).lineLimit(2).multilineTextAlignment(.leading)
            if chat.repository != nil || !chat.draft.isEmpty {
                HStack(spacing:RMLayout.rowGap) {
                    if let scope = chat.repository { Label(scope.fullName,systemImage:"folder").lineLimit(1) }
                    if !chat.draft.isEmpty { Label("Draft",systemImage:"pencil.line").foregroundStyle(RMPalette.accentText) }
                }.font(RMType.meta).foregroundStyle(RMPalette.secondary).labelStyle(RMCompactLabelStyle())
            }
        }
        .padding(.vertical,RMLayout.rowGap)
        .frame(maxWidth:.infinity,minHeight:RMLayout.rowHeight,alignment:.leading).contentShape(Rectangle())
        .multilineTextAlignment(.leading)
    }
}
/// Icon and text a quarter-unit apart, for metadata lines.
struct RMCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing:RMLayout.unit) { configuration.icon; configuration.title } }
}
struct ChatView: View {
    @Bindable var model: AppModel
    @FocusState private var focus: Bool
    @State private var models = false; @State private var repositories = false
    @State private var importer = false; @State private var query = ""
    @State private var reporting: ChatMessage?; @State private var export = false
    @State private var sessionDetails = false
    @State private var scrollFollowTask: Task<Void, Never>?
    @State private var scrollFollowID: UUID?
    @State private var transcriptTopInset: CGFloat = 0
    @Environment(\.rmUsesAdaptiveBars) private var adaptive
    @Environment(\.rmNavigationFocusRevision) private var navigationFocusRevision
    @Environment(\.rmWorkspaceVisible) private var visible
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var direction
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    private let bottomID = "latest"
    @ScaledMetric(relativeTo:.body) private var glyphSize = 20
    var body: some View {
        if let chat = model.conversation {
            ScrollViewReader { proxy in
                ScrollView {
                    // Streaming changes row heights continuously. Measure the
                    // transcript before following its footer, as SiteAgent does.
                    SessionTranscriptContent(model:model,chat:chat,query:query,
                        report:{ reporting = $0 },share:{ export = true })
                }
                .coordinateSpace(name:"chat.transcript")
                .accessibilityIdentifier("chat.transcript")
                .scrollEdgeEffectStyle(.soft,for:.top)
                .onScrollGeometryChange(for:CGFloat.self) { $0.contentInsets.top } action: { _, inset in transcriptTopInset = inset }
                // Native chat behavior: dragging the transcript lowers the keyboard; nothing re-lifts the composer afterwards.
                .scrollDismissesKeyboard(.interactively)
                // One owner moves the viewport. The old ID binding competed
                // with scrollTo and the default size-change bottom anchor.
                .onPreferenceChange(TranscriptMessageOffsets.self) { offsets in
                    guard visible,scenePhase == .active,!chat.followsLatest,model.conversation?.id == chat.id else { return }
                    let above = offsets.filter { $0.value <= transcriptTopInset + 24 }.max { $0.value < $1.value }
                    let closest = above ?? offsets.min { $0.value < $1.value }
                    if let id = closest?.key,chat.readingMessageID != id { model.editConversation { $0.readingMessageID = id } }
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting { cancelTranscriptFollow(); model.editConversation { $0.followsLatest = false } }
                }
                .onChange(of:TranscriptLayoutRevision(chat:chat,running:model.running.contains(chat.id))) { _, _ in followTranscriptBottom(proxy,conversationID:chat.id) }
                .onChange(of:chat.followsLatest) { _, following in
                    if following { followTranscriptBottom(proxy,conversationID:chat.id) } else { cancelTranscriptFollow() }
                }
                .onChange(of:chat.id,initial:true) { _, _ in
                    cancelTranscriptFollow()
                    if let saved = chat.readingMessageID,!chat.followsLatest {
                        var transaction = Transaction(); transaction.disablesAnimations = true
                        withTransaction(transaction) { proxy.scrollTo(saved,anchor:.top) }
                    } else { followTranscriptBottom(proxy,conversationID:chat.id) }
                }
                .onChange(of:navigationFocusRevision) { _,_ in if adaptive { focus = false } }
                .onChange(of:visible) { _, shown in
                    if shown { followTranscriptBottom(proxy,conversationID:chat.id) } else { cancelTranscriptFollow() }
                }
                .onChange(of:scenePhase) { _, phase in
                    if phase == .active { followTranscriptBottom(proxy,conversationID:chat.id) } else { cancelTranscriptFollow() }
                }
                .onDisappear { cancelTranscriptFollow() }
                .overlay(alignment:.bottomTrailing) {
                    if !chat.followsLatest {
                        Button("Return to latest",systemImage:"arrow.down") { model.editConversation { $0.followsLatest = true }; followTranscriptBottom(proxy,conversationID:chat.id) }
                            .labelStyle(.iconOnly).rmIconButton().padding(RMLayout.pageInset).accessibilityIdentifier("chat.latest")
                    }
                }
            }
            // Register the custom controls as bars so content blurs beneath them.
            .safeAreaBar(edge:.top,spacing:0) {
                VStack(spacing:0) {
                    if adaptive {
                        SessionIdentityButton(title:chat.title,workspace:chat.repository?.name ?? String(localized:"Personal workspace")) { sessionDetails = true }
                            .padding(.horizontal,RMLayout.pageInset).padding(.bottom,RMLayout.elementGap)
                    }
                    // Longer translations keep the complete scope selector above the mode control.
                    Group {
                        if typeSize.isAccessibilitySize { contextControls(chat,stacked:true) }
                        else {
                            ViewThatFits(in:.horizontal) {
                                contextControls(chat,stacked:false)
                                contextControls(chat,stacked:true)
                            }
                        }
                    }.padding(.horizontal,RMLayout.pageInset).padding(.bottom,RMLayout.elementGap)
                    if model.chatSearchVisible {
                        HStack(spacing:RMLayout.elementGap) {
                            Image(systemName:"magnifyingglass").foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
                            TextField("Search this conversation",text:$query).submitLabel(.search)
                        }.font(RMType.body).padding(.horizontal,RMLayout.rowGap).frame(minHeight:RMLayout.controlCompact)
                            .background(RMPalette.input,in:Capsule()).padding(.horizontal,RMLayout.pageInset).padding(.bottom,RMLayout.elementGap)
                    }
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                RMFoldSafeControls {
                    VStack(spacing:0) {
                        if let profile = model.data.providers.first(where:{ $0.id == chat.providerID }),profile.usesChatGPT,
                           AppChatGPTConfiguration.enabled,model.chatGPTSessions[profile.id]?.planUsageEnabled == true { ChatGPTUsageStrip() }
                        if model.voiceConversation { VoiceMiniView(model:model) }
                        RMComposer(text:Binding(get:{ model.data.conversations.first(where:{ $0.id == chat.id })?.draft ?? "" },set:{ value in
                            model.updateDraft(value,in:chat.id)
                        }),focus:$focus,
                            attachments:chat.attachments.map { RMAttachment(id:$0.id.uuidString,name:$0.name) },isResponding:model.running.contains(chat.id) || model.stopping.contains(chat.id),
                            canSend:!chat.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,canStop:!model.stopping.contains(chat.id),canAdd:true,canRemove:true,
                            microphone:AnyView(Button { if model.voicePhase == .listening { model.voice?.finishDictation() } else { model.startDictation() } } label: { Image(systemName:model.voicePhase == .listening ? "mic.fill" : "mic").font(.system(size:min(glyphSize,RMLayout.glyphMaximum),weight:.medium)).foregroundStyle(RMPalette.text).frame(width:RMLayout.minimumHit,height:RMLayout.minimumHit) }.accessibilityLabel("Dictate").accessibilityIdentifier("chat.dictation")),
                            modelControl:AnyView(ComposerModelButton(model:model,chat:chat) { models = true }),
                            onVoice:{ model.startDictation(continuous:true) },reasoningControl:AnyView(ReasoningControl(model:model,conversation:chat)),
                            onAdd:{ importer = true },onRemove:{ id in model.editConversation { $0.attachments.removeAll { $0.id.uuidString == id } } },
                            onSend:{ _,_ in
                                focus = false
                                // Without a model, sending can only fail; open the picker instead of an error.
                                if chat.providerID == nil || chat.modelID.isEmpty, !chat.draft.hasPrefix("/") { models = true } else { model.send() }
                            },onStop:{ model.stop() })
                    }
                }
            }
            .onChange(of:chat.id,initial:true) { _,_ in if visible { model.prepareSession(chat.id) } }
            .onChange(of:visible) { _, value in
                if value { model.prepareSession(chat.id) } else { model.rememberSession(chat.id); focus = false }
            }
            .onDisappear { model.rememberSession(chat.id) }
            // A hidden search field must not keep filtering the transcript.
            .onChange(of:model.chatSearchVisible) { _, shown in if !shown { query = "" } }
            .sheet(isPresented:$models) { ModelPickerView(model:model) }
            .sheet(isPresented:$sessionDetails) {
                SessionDetailsView(model:model)
                    .environment(\.dynamicTypeSize,typeSize).environment(\.layoutDirection,direction)
                    .environment(\.rmReduceMotionOverride,reduceMotion)
            }
            .sheet(isPresented:$repositories) { RepositoryPickerView(model:model) }
            .sheet(isPresented:$export) { BackupView(model:model,conversationOnly:true) }
            .sheet(item:$reporting) { message in
                let profile = model.data.providers.first { $0.id == (message.providerContinuation?.profileID ?? chat.providerID) }
                ReportResponseView(message:message,source:[profile?.title ?? "",message.providerContinuation?.modelID ?? chat.modelID].filter { !$0.isEmpty }.joined(separator:" · "))
            }
            .fileImporter(isPresented:$importer,allowedContentTypes:[.text,.json,.pdf,.sourceCode,.data]) { result in if case .success(let url) = result { Task { await model.importAttachment(url) } } }
        } else { ContentUnavailableView { Label("Start a conversation",systemImage:"bubble.left") } actions: { Button("New chat",action:model.newChat).rmProminentButton().frame(maxWidth:320) } }
    }
    @ViewBuilder private func contextControls(_ chat:Conversation,stacked:Bool) -> some View {
        if adaptive { duoContextControls(chat,stacked:stacked) }
        else { classicContextControls(chat,stacked:stacked) }
    }
    private func duoContextControls(_ chat:Conversation,stacked:Bool) -> some View {
        Group {
            if stacked {
                VStack(alignment:.leading,spacing:RMLayout.elementGap) {
                    repositoryContext(chat,compact:false)
                    HStack(spacing:RMLayout.elementGap) {
                        modelContext(chat).frame(maxWidth:.infinity,alignment:.leading)
                        runMode(chat)
                    }
                }
            } else {
                HStack(spacing:RMLayout.elementGap) {
                    repositoryContext(chat,compact:true)
                    modelContext(chat).fixedSize(horizontal:true,vertical:false)
                    Spacer(minLength:0)
                    runMode(chat)
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func repositoryContext(_ chat:Conversation,compact:Bool) -> some View {
        Button { repositories = true } label: {
            HStack(spacing:RMLayout.unit+2) { Image(systemName:"folder"); Text(chat.repository.map { "\($0.name) · \($0.branch)" } ?? String(localized:"Select repository")).lineLimit(1).truncationMode(.middle); Image(systemName:"chevron.down").font(RMType.meta.weight(.bold)).foregroundStyle(RMPalette.secondary) }
        }.rmChip().fixedSize(horizontal:compact,vertical:false).accessibilityLabel(chat.repository.map { String(localized:"Repository \($0.fullName), branch \($0.branch)") } ?? String(localized:"Select repository")).accessibilityIdentifier("chat.repositoryContext")
    }
    private func modelContext(_ chat:Conversation) -> some View {
        let name = model.data.providers.first(where:{ $0.id == chat.providerID })?.models.first(where:{ $0.id == chat.modelID })?.displayName ?? chat.modelID
        return DuoChatModelButton(title:chat.modelID.isEmpty ? String(localized:"Choose model") : name,selected:!chat.modelID.isEmpty) { models = true }
    }
    private func runMode(_ chat:Conversation) -> some View {
        Picker("Run mode",selection:Binding(get:{ chat.mode },set:{ mode in model.stop(); model.editConversation { $0.mode = mode } })) { Text("Plan").tag(RunMode.plan); Text("Act").tag(RunMode.act) }
            .pickerStyle(.segmented).fixedSize().accessibilityIdentifier("chat.runMode")
    }
    private func classicContextControls(_ chat:Conversation,stacked:Bool) -> some View {
        (stacked ? AnyLayout(VStackLayout(alignment:.leading,spacing:RMLayout.elementGap)) : AnyLayout(HStackLayout(spacing:RMLayout.elementGap))) {
            Button { repositories = true } label: {
                HStack(spacing:RMLayout.unit+2) { Image(systemName:"folder"); Text(chat.repository.map { "\($0.name) · \($0.branch)" } ?? String(localized:"Select repository")).lineLimit(1).truncationMode(.middle); Image(systemName:"chevron.down").font(RMType.meta.weight(.bold)).foregroundStyle(RMPalette.secondary) }
            }.rmChip().fixedSize(horizontal:!stacked,vertical:false).accessibilityLabel(chat.repository.map { String(localized:"Repository \($0.fullName), branch \($0.branch)") } ?? String(localized:"Select repository")).accessibilityIdentifier("chat.repositoryContext")
            if !stacked { Spacer(minLength:0) }
            Picker("Run mode",selection:Binding(get:{ chat.mode },set:{ mode in model.stop(); model.editConversation { $0.mode = mode } })) { Text("Plan").tag(RunMode.plan); Text("Act").tag(RunMode.act) }.pickerStyle(.segmented).fixedSize().accessibilityIdentifier("chat.runMode")
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    // SiteAgent's stream fix: let layout settle, coalesce updates, and never
    // animate a scroll toward an anchor that reasoning or tool content is moving.
    private func followTranscriptBottom(_ proxy: ScrollViewProxy, conversationID: UUID) {
        guard scrollFollowTask == nil,visible,scenePhase == .active,
              model.conversation?.id == conversationID,model.conversation?.followsLatest == true else { return }
        let lease = UUID(); scrollFollowID = lease
        scrollFollowTask = Task { @MainActor in
            defer { if scrollFollowID == lease { scrollFollowTask = nil; scrollFollowID = nil } }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard !Task.isCancelled,scrollFollowID == lease,
                  model.conversation?.id == conversationID,model.conversation?.followsLatest == true else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(bottomID,anchor:.bottom) }
        }
    }
    private func cancelTranscriptFollow() {
        scrollFollowID = nil; scrollFollowTask?.cancel(); scrollFollowTask = nil
    }
}


private struct SessionTranscriptContent: View {
    @Bindable var model: AppModel
    let chat: Conversation
    let query: String
    let report: (ChatMessage) -> Void
    let share: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:RMLayout.groupGap) {
            if chat.messages.isEmpty {
                RMEmptyState("Start with a question",detail:"Ask about your code, plan a change, or attach a document. Choose a model above; Plan mode keeps repository tools read-only.")
            }
            if let notice = chat.contextNotice { RMContextCompactionBanner(message:notice) }
            ForEach((chat.modelChanges ?? []).filter { $0.beforeMessageID == nil }) { SessionModelChangeRow(change:$0) }
            ForEach(chat.messages.filter { $0.role != .tool && $0.role != .system && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.reasoning.localizedCaseInsensitiveContains(query)) }) { message in
                SessionMessageCell(model:model,chatID:chat.id,message:message,
                    streaming:model.running.contains(chat.id) && message.id == chat.messages.last?.id,
                    latest:message.id == chat.messages.last?.id && !model.running.contains(chat.id),report:report,share:share)
                    .id(message.id)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key:TranscriptMessageOffsets.self,value:[message.id:geometry.frame(in:.named("chat.transcript")).minY])
                        }
                    }
                ForEach((chat.modelChanges ?? []).filter { $0.beforeMessageID == message.id }) { SessionModelChangeRow(change:$0) }
            }
            if let recap = model.recaps[chat.id] { SessionRecapView(recap:recap) { model.dismissRecap(chat.id) } }
            if model.stopping.contains(chat.id) {
                Label("Stopping…",systemImage:"circle.dotted").font(RMType.meta).foregroundStyle(RMPalette.secondary).accessibilityIdentifier("chat.stopping")
            } else if model.running.contains(chat.id), let reply = chat.messages.last, !reply.text.isEmpty || !reply.tools.isEmpty {
                RMTimedActivityLabel(title:String(localized:"Working"),startedAt:reply.created)
            }
            Color.clear.frame(height:4).id("latest")
        }.padding(.horizontal,RMLayout.pageInset).padding(.top,RMLayout.pageInset).frame(maxWidth:760).frame(maxWidth:.infinity)
    }
}

private struct SessionMessageCell: View {
    @Bindable var model: AppModel
    let chatID: UUID
    let message: ChatMessage
    let streaming: Bool
    let latest: Bool
    let report: (ChatMessage) -> Void
    let share: () -> Void
    var body: some View {
        MessageRow(message:message,streaming:streaming,latest:latest,
            copy:{ SafeClipboard.copyResponse(message.text) },regenerate:model.regenerate,
            follow:{ model.follow($0,after:message.id) },
            read:{ model.voice?.speak(message.text,voiceID:model.data.preferences.voiceID,rate:model.data.preferences.speechRate) },
            concern:{ report(message) },share:share,review:{ model.selection = .changes },
            toolsExpanded:model.sessionState(chatID).expandedToolGroups.contains(message.id),onToolsExpandedChange:{ expanded in
                model.updateSessionState(chatID) { state in
                    if expanded { state.expandedToolGroups.insert(message.id) } else { state.expandedToolGroups.remove(message.id) }
                }
            }).equatable()
    }
}

private struct TranscriptMessageOffsets: PreferenceKey {
    static let defaultValue: [UUID:CGFloat] = [:]
    static func reduce(value:inout [UUID:CGFloat],nextValue:() -> [UUID:CGFloat]) { value.merge(nextValue(),uniquingKeysWith:{ _,new in new }) }
}

private struct TranscriptLayoutRevision: Equatable {
    let count: Int; let lastID: UUID?; let textBytes: Int; let reasoningBytes: Int
    let reasoningActive: Bool; let tools: [String]; let approval: Bool; let running: Bool; let notice: String?
    init(chat: Conversation, running: Bool) {
        let last = chat.messages.last
        count = chat.messages.count; lastID = last?.id
        textBytes = last?.text.utf8.count ?? 0; reasoningBytes = last?.reasoning.utf8.count ?? 0
        reasoningActive = last?.reasoningStartedAt != nil && last?.reasoningSeconds == nil
        tools = last?.tools.map(\.id) ?? []; approval = last?.tools.contains { $0.status == .approval } ?? false
        self.running = running; notice = chat.contextNotice
    }
}
/// The chat's model picker, shown in the top bar like a native principal toolbar item.
struct ChatModelButton: View {
    @Bindable var model: AppModel; @State private var picking = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    var body: some View {
        SessionIdentityButton(title:model.conversation?.title ?? String(localized:"New chat"),workspace:model.conversation?.repository?.name ?? String(localized:"Personal workspace")) { picking = true }
            .sheet(isPresented:$picking) {
                SessionDetailsView(model:model)
                    .environment(\.dynamicTypeSize,typeSize).environment(\.layoutDirection,direction)
                    .environment(\.rmReduceMotionOverride,reduceMotion)
            }
    }
}
/// Conversation actions, beside New chat in the top bar.
struct ChatActionsMenu: View {
    @Bindable var model: AppModel
    @State private var details = false; @State private var export = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    var body: some View {
        if let chat = model.conversation {
            let metadata = model.data.providers.first(where:{ $0.id == chat.providerID })?.models.first(where:{ $0.id == chat.modelID })
            let ratio = SessionContext.contextRatio(chat,metadata:metadata)
            Button { details = true } label: {
                Image(systemName:"ellipsis").overlay {
                    if let ratio { Circle().trim(from:0,to:min(1,max(0,ratio))).stroke(RMPalette.text,lineWidth:1.5).rotationEffect(.degrees(-90)).frame(width:40,height:40).allowsHitTesting(false) }
                }
            }
            .rmIconButton().accessibilityLabel("Session details")
            .accessibilityValue(ratio.map { String(localized:"Estimated context \($0.formatted(.percent.precision(.fractionLength(0)))) used") } ?? String(localized:"Context unavailable"))
            .accessibilityIdentifier("chat.actions")
            .sheet(isPresented:$details) {
                SessionDetailsView(model:model)
                    .environment(\.dynamicTypeSize,typeSize).environment(\.layoutDirection,direction)
                    .environment(\.rmReduceMotionOverride,reduceMotion)
            }
        }
    }
}
struct MessageRow: View, Equatable {
    let message: ChatMessage; let streaming: Bool; let latest: Bool; let copy: () -> Void; let regenerate: () -> Void
    let follow: (String) -> Void; let read: () -> Void; let concern: () -> Void; let share: () -> Void; let review: () -> Void
    let toolsExpanded: Bool
    let onToolsExpandedChange: (Bool) -> Void
    @Environment(\.rmUsesAdaptiveBars) private var adaptive
    @Environment(\.displayScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var details = false; @State private var copied = false
    nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message && lhs.streaming == rhs.streaming && lhs.latest == rhs.latest && lhs.toolsExpanded == rhs.toolsExpanded
    }
    var body: some View {
        if message.role == .user {
            RMUserBubbleLayout(displayScale:scale) {
                Text(message.text).font(RMType.body).textSelection(.enabled).padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap)
                    .background(RMPalette.input,in:RoundedRectangle(cornerRadius:RMLayout.bubbleCorner,style:.continuous))
            }
        } else {
            VStack(alignment:.leading,spacing:RMLayout.rowGap) {
                if streaming && message.text.isEmpty && message.reasoning.isEmpty && message.tools.isEmpty { RMTimedActivityLabel(title:String(localized:"Working…"),startedAt:message.created) }
                if !message.reasoning.isEmpty { RMReasoningBlock(content:message.reasoning,isOpen:streaming && message.reasoningSeconds == nil,seconds:message.reasoningSeconds,startedAt:message.reasoningStartedAt,isResponding:streaming) }
                if !message.tools.isEmpty {
                    RMToolActivityGroup(events:message.tools.map { tool in
                        RMToolEvent(id:tool.id,title:RMLocalization.fieldName(tool.name),detail:RepositorySecretScanner.scan(tool.detail).redacted,
                            status:tool.status == .failure ? .failure : tool.status == .cancelled ? .cancelled : tool.status == .running ? .running : tool.status == .approval ? .approval : .success,
                            arguments:message.calls.first(where:{ $0.id == tool.id }).map { RepositorySecretScanner.scan(String(decoding:$0.arguments.encoded,as:UTF8.self)).redacted })
                    },isRunning:streaming,expanded:Binding(get:{ toolsExpanded },set:{ value in onToolsExpandedChange(value) }))
                    if message.tools.contains(where:{ $0.status == .approval }) { Button("Review pending changes",systemImage:"checkmark.shield",action:review).rmSecondaryButton().accessibilityIdentifier("chat.review") }
                }
                if !message.text.isEmpty { RMMarkdown(message.text,isStreaming:streaming).equatable() }
                if let issue = message.responseIssue {
                    RMInlineNotice(title:"No reply received",detail:issue,symbol:"exclamationmark.circle",isError:true)
                        .accessibilityIdentifier("chat.responseIssue")
                }
                if !streaming {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:RMLayout.unit)) : AnyLayout(HStackLayout(spacing:RMLayout.elementGap))) {
                      HStack(spacing:adaptive ? RMLayout.unit : 0) {
                        Button(copied ? String(localized:"Copied") : String(localized:"Copy"),systemImage:copied ? "checkmark" : "doc.on.doc") {
                            copy(); copied = true; Task { try? await Task.sleep(for:.seconds(1.5)); copied = false }
                        }.labelStyle(.iconOnly).frame(width:44,height:44).contentTransition(.symbolEffect(.replace)).sensoryFeedback(.success,trigger:copied) { _,new in new }.disabled(message.text.isEmpty)
                        Button("Read aloud",systemImage:"speaker.wave.2",action:read).labelStyle(.iconOnly).frame(width:44,height:44).disabled(message.text.isEmpty)
                        // Regenerate and follow-ups act on the latest exchange, so only the latest reply offers them.
                        if latest { Button("Regenerate",systemImage:"arrow.clockwise",action:regenerate).labelStyle(.iconOnly).frame(width:44,height:44) }
                        Menu {
                            if latest {
                                Button("Continue") { follow(String(localized:"Continue your previous response.")) }.accessibilityIdentifier("chat.response.continue")
                                Button("Shorter") { follow(String(localized:"Make your previous response shorter.")) }
                                Button("Formal") { follow(String(localized:"Rewrite your previous response in a formal tone.")) }
                                Button("Explain") { follow(String(localized:"Explain your previous response in more detail.")) }
                            }
                            Button("Encrypted share",action:share)
                            Button("Response details") { details = true }
                            if !ReportResponseView.address.isEmpty { Button("Report response…",systemImage:"flag",action:concern) }
                        } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("More response actions")
                      }.buttonStyle(RMInlineIconButtonStyle())
                        if !typeSize.isAccessibilitySize { Spacer(minLength:0) }
                        if let u = message.usage {
                            Text("\(u.input.map(String.init) ?? "?") in · \(u.output.map(String.init) ?? "?") out")
                                .font(RMType.meta).fixedSize(horizontal:false,vertical:true)
                        }
                    }.foregroundStyle(RMPalette.secondary)
                    if let cost = message.pricing?.estimateUSD(message.usage) {
                        Text("Estimated cost \(cost,format:.currency(code:"USD").precision(.fractionLength(2...6)))")
                            .font(RMType.meta).foregroundStyle(RMPalette.secondary)
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            .sheet(isPresented:$details) {
                NavigationStack { RMForm { LabeledContent("Message",value:message.id.uuidString); LabeledContent("Finish",value:message.finishReason ?? String(localized:"unknown")); LabeledContent("Created",value:message.created.formatted()); if let decision = message.reasoningDecision { LabeledContent("Reasoning",value:decision.label); Text(decision.explanation).font(RMType.meta) }; LabeledContent("Reasoning tokens",value:message.usage?.reasoning.map(String.init) ?? String(localized:"unknown")); LabeledContent("Input tokens",value:message.usage?.input.map(String.init) ?? String(localized:"unknown")); LabeledContent("Output tokens",value:message.usage?.output.map(String.init) ?? String(localized:"unknown")); if let cost = message.pricing?.estimateUSD(message.usage) { LabeledContent("Estimated cost",value:cost.formatted(.currency(code:"USD").precision(.fractionLength(2...6)))); Text("Uses the model prices captured when this response began and reported counts across all tool rounds. Discounts, cache pricing, and destination fees may differ.").font(RMType.meta) } }.navigationTitle("Response details").toolbar { Button("Done") { details = false } } }
            }
        }
    }
}
struct ModelPickerView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var query = ""; @State private var manual:[UUID:String] = [:]
    @State private var privacySelection:PrivacySelection?
    private struct PrivacySelection:Identifiable { let id = UUID(); let profile:ProviderProfile; let model:String; let notice:String }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    if model.data.providers.isEmpty {
                        RMEmptyState("No providers yet",detail:"Add a provider to choose a model for this conversation.",symbol:"server.rack")
                    }
                    ForEach(model.data.providers) { profile in
                        let models = profile.models.filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) || $0.displayName?.localizedCaseInsensitiveContains(query) == true }
                        // One card per provider: its identity, then its models aligned under its name.
                        RMCard {
                            RMRow(profile.title,detail:ProviderMark.destination(profile),accessory:.value(profile.models.count == 1 ? String(localized:"1 model") : String(localized:"\(profile.models.count) models"))) { ProviderMark(profile:profile) } trailing: { EmptyView() }
                            ForEach(models) { item in
                                let selected = model.conversation?.providerID == profile.id && model.conversation?.modelID == item.id
                                Button { choose(profile,item.id) } label: {
                                    RMRow(item.displayName ?? item.id,detail:ModelPickerView.summary(item)) {
                                        Image(systemName:selected ? "checkmark.circle.fill" : "circle").font(RMType.title)
                                            .foregroundStyle(selected ? RMPalette.accentText : RMPalette.line).frame(width:RMLayout.tile)
                                    } trailing: { EmptyView() }
                                }.buttonStyle(RMPressButtonStyle()).disabled(item.availability != nil)
                                    .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("model.\(item.id)")
                            }
                            if profile.preset != .apple && !profile.usesChatGPT { manualEntry(profile) }
                        }
                    }
                    Button(model.data.providers.isEmpty ? String(localized:"Add a provider") : String(localized:"Configure providers")) { model.selection = .providers; dismiss() }
                        .rmSecondaryButton()
                }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
            }
            .background(RMPageBackground()).searchable(text:$query,prompt:"Search models")
            .navigationTitle("Model").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Review model privacy",isPresented:Binding(get:{ privacySelection != nil },set:{ if !$0 { privacySelection = nil } }),presenting:privacySelection) { selection in
                Button("Cancel",role:.cancel) { privacySelection = nil }
                Button("Accept and select") { Task { do { try await model.consentToModel(profile:selection.profile,model:selection.model); model.selectModel(profile:selection.profile,model:selection.model); dismiss() } catch { model.error = RMError.consentRequired.localizedDescription } } }
            } message: { selection in Text("\(selection.profile.title) · \(selection.model)\n\(selection.profile.endpoint)\n\n\(selection.notice)\n\nPrivacy terms: docs.opencode.ai/docs/\(selection.profile.preset == .openCodeGo ? "go" : "zen")/") }
        }
    }
    /// A model ID that is not in the catalog, typed into the provider's own card.
    private func manualEntry(_ profile:ProviderProfile) -> some View {
        let text = Binding(get:{ manual[profile.id] ?? "" },set:{ manual[profile.id] = $0 })
        return HStack(spacing:RMLayout.rowGap) {
            Image(systemName:"plus").font(RMType.rowTitle).foregroundStyle(RMPalette.secondary).frame(width:RMLayout.tile).accessibilityHidden(true)
            TextField("Other model ID",text:text).font(RMType.body).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.done)
                .onSubmit { useManual(profile) }
            Button("Use") { useManual(profile) }.rmChip().disabled(text.wrappedValue.trimmingCharacters(in:.whitespaces).isEmpty)
        }.padding(.horizontal,RMLayout.cardInset).frame(minHeight:RMLayout.rowHeight)
    }
    private func useManual(_ profile:ProviderProfile) {
        if let id = try? InputValidation.model(manual[profile.id]?.trimmingCharacters(in:.whitespaces) ?? "") { choose(profile,id) }
        else { model.error = String(localized:"Model IDs use letters, numbers, and - . _ / : only.") }
    }
    /// Availability first; otherwise the limits and prices this app knows, never guesses.
    static func summary(_ item:ModelMetadata) -> String? {
        if let status = item.availability { return status }
        var parts:[String] = []
        if let context = item.contextTokens { parts.append(String(localized:"\(context.formatted(.number.notation(.compactName))) context")) }
        if let input = item.inputCostPerMillion, let output = item.outputCostPerMillion {
            parts.append(String(localized:"$\(input.formatted(.number.precision(.fractionLength(0...2)))) / $\(output.formatted(.number.precision(.fractionLength(0...2)))) per M"))
        }
        return parts.isEmpty ? nil : parts.joined(separator:" · ")
    }
    private func choose(_ profile:ProviderProfile,_ id:String) {
        if let notice = ProviderDisclosure.modelNotice(profile:profile,model:id),profile.privacyConsentedModels?.contains(id) != true { privacySelection = PrivacySelection(profile:profile,model:id,notice:notice) }
        else { model.selectModel(profile:profile,model:id); dismiss() }
    }
}
/// A provider's identity tile: Apple and custom endpoints use symbols, hosted APIs an ink monogram.
struct ProviderMark: View {
    let preset: ProviderPreset; let title: String
    init(profile:ProviderProfile) { preset = profile.preset; title = profile.title }
    init(preset:ProviderPreset) { self.preset = preset; title = preset.title }
    var body: some View {
        switch preset {
        case .apple: RMIconTile("apple.intelligence")
        case .custom: RMIconTile("network")
        default: RMMonogram(preset.title)
        }
    }
    static func destination(_ profile:ProviderProfile) -> String {
        if profile.usesChatGPT {
            if let account = profile.chatGPTAccount { return "\(account.label) · \(account.registrationLabel)" }
            return String(localized:"ChatGPT plan")
        }
        return profile.preset == .apple ? "Apple Intelligence" : URL(string:profile.endpoint)?.host ?? profile.endpoint
    }
}
struct ConversationDetailsView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            RMForm {
                TextField("Title",text:binding(\.title))
                Section("Project instructions") { TextEditor(text:binding(\.instructions)).frame(minHeight:120) }
                Section("User-controlled memory") { TextEditor(text:binding(\.memory)).frame(minHeight:120); Text("Only this explicit text is used as persistent context memory.").font(RMType.meta) }
                Section("Context mentions") { Text("Mention @path/to/file, @issue:123, @pr:123, or an attached document. Use read/search tools to retrieve bounded context on the selected repository.").font(RMType.meta) }
            }.navigationTitle("Conversation").toolbar { Button("Done") { dismiss() } }
        }
    }
    private func binding(_ path: WritableKeyPath<Conversation,String>) -> Binding<String> { Binding(get:{ model.conversation?[keyPath:path] ?? "" },set:{ value in model.editConversation { $0[keyPath:path] = value } }) }
}
/// Reports a model response to the developer through the person's own mail app. Nothing is sent without them.
struct ReportResponseView: View {
    let message: ChatMessage; let source: String
    @Environment(\.dismiss) private var dismiss; @Environment(\.openURL) private var openURL
    @State private var reason = ContentReport.reasons[0]; @State private var note = ""
    @State private var includeResponse = true; @State private var noMailApp = false
    /// Empty hides reporting entirely (see Info.plist).
    static let address = (Bundle.main.object(forInfoDictionaryKey:"RMSupportEmail") as? String ?? "").trimmingCharacters(in:.whitespaces)
    private var address: String { Self.address }
    var body: some View {
        NavigationStack {
            RMForm {
                Section("What's wrong with this response?") {
                    Picker("Reason",selection:$reason) { ForEach(ContentReport.reasons,id:\.self) { Text($0) } }.pickerStyle(.inline).labelsHidden()
                }
                Section("Details") { TextField("Optional",text:$note,axis:.vertical).lineLimit(3...8) }
                Section {
                    Toggle("Include the response text",isOn:$includeResponse)
                } footer: {
                    Text("Your mail app opens a report to \(address) for you to review before sending. Credentials in the response are masked. \(source.isEmpty ? "" : String(localized:"This response came from \(source); you can also report it to that provider."))")
                }
            }
            .navigationTitle("Report response").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Send…") { send() }.disabled(address.isEmpty) }
            }
            .alert("No mail app is set up",isPresented:$noMailApp) {
                Button("Copy address") { SafeClipboard.copyResponse(address) }
                Button("OK",role:.cancel) {}
            } message: { Text("Send your report to \(address).") }
        }
    }
    private func send() {
        guard let url = ContentReport.mailURL(to:address,reason:reason,note:note,source:source,messageID:message.id,created:message.created,response:includeResponse ? message.text : nil) else { noMailApp = true; return }
        openURL(url) { opened in if opened { dismiss() } else { noMailApp = true } }
    }
}

private struct DuoChatModelButton: View {
    let title: String; let selected: Bool; let action: () -> Void
    var body: some View {
        Button(action:action) { Label(title,systemImage:"cpu").labelStyle(.titleAndIcon).lineLimit(1).truncationMode(.middle) }
            .rmChip().accessibilityLabel(selected ? String(localized:"Model \(title)") : String(localized:"Choose model"))
            .accessibilityIdentifier("chat.modelPicker")
    }
}
