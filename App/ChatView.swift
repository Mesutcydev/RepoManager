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
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    // The top bar owns New chat; the heading owns list options.
                    RMPageHeading("Chats") {
                        Menu {
                            Button("Import encrypted share inbox",systemImage:"square.and.arrow.down") { Task { await model.importInbox() } }
                            Button(archived ? "Show current chats" : "Show archived chats",systemImage:"archivebox") { archived.toggle() }
                        } label: { Image(systemName:"ellipsis") }
                            .rmIconButton().accessibilityLabel("Conversation history actions")
                    }
                    if model.data.conversations.isEmpty {
                        VStack(alignment:.leading,spacing:RMLayout.cardInset) {
                            RMEmptyState("What are you working on?",detail:"Connect a provider and begin a conversation. Add a repository when you want to inspect files or plan a change.",symbol:"bubble.left.and.bubble.right")
                            Button("Start a chat",action:model.newChat).rmProminentButton()
                            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:RMLayout.elementGap)) : AnyLayout(HStackLayout(spacing:RMLayout.elementGap))) {
                                Button("Providers") { model.selection = .providers }.rmSecondaryButton()
                                Button("GitHub") { model.selection = .repositories }.rmSecondaryButton()
                            }
                        }
                    } else if visible.isEmpty {
                        RMEmptyState(!query.isEmpty ? "No matches" : archived ? "No archived chats" : "No current chats",
                                     detail:!query.isEmpty ? "No conversation matches “\(query)”." : archived ? "Archived conversations appear here." : "Start a chat with the compose button.",
                                     symbol:!query.isEmpty ? "magnifyingglass" : "archivebox")
                    } else {
                        RMCard(archived ? "Archived" : "Recent",dividerInset:RMLayout.cardInset) {
                            ForEach(visible) { chat in
                                Button { model.selectChat(chat.id) } label: { ChatRow(chat:chat) }
                                    .buttonStyle(RMPressButtonStyle()).accessibilityIdentifier("history.\(chat.id)")
                                    .contextMenu {
                                        Button(chat.pinned ? "Unpin" : "Pin",systemImage:"pin") { mutate(chat.id) { $0.pinned.toggle() } }
                                        Button("Rename",systemImage:"pencil") { name = chat.title; renameID = chat.id }
                                        Button("Fork",systemImage:"arrow.triangle.branch") { model.fork(chat.id) }
                                        Button(chat.archived ? "Unarchive" : "Archive",systemImage:"archivebox") { mutate(chat.id) { $0.archived.toggle() } }
                                        Button("Delete",systemImage:"trash",role:.destructive) { deleting = chat }
                                    }
                            }
                        }
                    }
                }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).searchable(text:$query,prompt:"Search conversations").navigationBarHidden(true).accessibilityIdentifier("history.list")
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
    var body: some View {
        VStack(alignment:.leading,spacing:RMLayout.unit) {
            HStack(alignment:.firstTextBaseline,spacing:RMLayout.elementGap) {
                if chat.pinned { Image(systemName:"pin.fill").font(RMType.meta).foregroundStyle(RMPalette.secondary).accessibilityLabel("Pinned") }
                Text(chat.title).font(RMType.rowTitle).foregroundStyle(RMPalette.text).lineLimit(1)
                Spacer(minLength:RMLayout.elementGap)
                Text(chat.modified,format:.relative(presentation:.named)).font(RMType.meta).foregroundStyle(RMPalette.secondary).lineLimit(1)
            }
            Text(chat.messages.last?.text ?? "No messages yet").font(RMType.detail).foregroundStyle(RMPalette.secondary).lineLimit(2).multilineTextAlignment(.leading)
            if chat.repository != nil || !chat.draft.isEmpty {
                HStack(spacing:RMLayout.rowGap) {
                    if let scope = chat.repository { Label(scope.fullName,systemImage:"folder").lineLimit(1) }
                    if !chat.draft.isEmpty { Label("Draft",systemImage:"pencil.line").foregroundStyle(RMPalette.accentText) }
                }.font(RMType.meta).foregroundStyle(RMPalette.secondary).labelStyle(RMCompactLabelStyle())
            }
        }
        .padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap)
        .frame(maxWidth:.infinity,minHeight:RMLayout.rowHeight,alignment:.leading).contentShape(Rectangle())
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
    @Environment(\.rmWorkspaceVisible) private var visible
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.rmMotionIsReduced) private var reduced
    @Environment(\.scenePhase) private var scenePhase
    private let bottomID = "latest"
    @ScaledMetric(relativeTo:.body) private var glyphSize = 20
    var body: some View {
        if let chat = model.conversation {
            VStack(spacing:0) {
                // The model and conversation actions live in the top bar; scope and mode share one row.
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:RMLayout.elementGap)) : AnyLayout(HStackLayout(spacing:RMLayout.elementGap))) {
                    Button { repositories = true } label: {
                        HStack(spacing:RMLayout.unit+2) { Image(systemName:"folder"); Text(chat.repository.map { "\($0.name) · \($0.branch)" } ?? "Select repository").lineLimit(1).truncationMode(.middle); Image(systemName:"chevron.down").font(RMType.meta.weight(.bold)).foregroundStyle(RMPalette.secondary) }
                    }.rmChip().accessibilityLabel(chat.repository.map { "Repository \($0.fullName), branch \($0.branch)" } ?? "Select repository").accessibilityIdentifier("chat.repositoryContext")
                    Spacer(minLength:0)
                    Picker("Run mode",selection:Binding(get:{ chat.mode },set:{ mode in model.stop(); model.editConversation { $0.mode = mode } })) { Text("Plan").tag(RunMode.plan); Text("Act").tag(RunMode.act) }.pickerStyle(.segmented).fixedSize()
                }.padding(.horizontal,RMLayout.pageInset).padding(.bottom,RMLayout.elementGap)
                if model.chatSearchVisible {
                    HStack(spacing:RMLayout.elementGap) {
                        Image(systemName:"magnifyingglass").foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
                        TextField("Search this conversation",text:$query).submitLabel(.search)
                    }.font(RMType.body).padding(.horizontal,RMLayout.rowGap).frame(minHeight:RMLayout.controlCompact)
                        .background(RMPalette.input,in:Capsule()).padding(.horizontal,RMLayout.pageInset).padding(.bottom,RMLayout.elementGap)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:RMLayout.groupGap) {
                            if chat.messages.isEmpty {
                                RMEmptyState("Start with a question",detail:"Ask about your code, plan a change, or attach a document. Choose a model above; Plan mode keeps repository tools read-only.",symbol:"sparkle")
                            }
                            if let notice = chat.contextNotice { RMContextCompactionBanner(message:notice) }
                            ForEach(chat.messages.filter { $0.role != .tool && $0.role != .system && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.reasoning.localizedCaseInsensitiveContains(query)) }) { message in
                                MessageRow(message:message,streaming:model.running.contains(chat.id) && message.id == chat.messages.last?.id,
                                    latest:message.id == chat.messages.last?.id && !model.running.contains(chat.id),
                                    copy:{ SafeClipboard.copyResponse(message.text) },regenerate:model.regenerate,
                                    follow:{ model.send($0) },read:{ model.voice?.speak(message.text,voiceID:model.data.preferences.voiceID,rate:model.data.preferences.speechRate) },
                                    concern:{ reporting = message },share:{ export = true },review:{ model.selection = .changes })
                                    .id(message.id)
                                    .transition(reduced ? .opacity : .opacity.combined(with:.offset(y:6)))
                            }
                            Color.clear.frame(height:4).id(bottomID)
                        }.padding(.horizontal,RMLayout.pageInset).padding(.top,RMLayout.pageInset).frame(maxWidth:760).frame(maxWidth:.infinity)
                            .scrollTargetLayout()
                            .animation(reduced || !visible || scenePhase != .active ? nil : .spring(response:0.32,dampingFraction:1),value:chat.messages.count)
                    }
                    .defaultScrollAnchor(.bottom)
                    // Native chat behavior: dragging the transcript lowers the keyboard; nothing re-lifts the composer afterwards.
                    .scrollDismissesKeyboard(.interactively)
                    .scrollPosition(id:Binding<UUID?>(get:{ chat.readingMessageID },set:{ value in if !chat.followsLatest { model.editConversation { $0.readingMessageID = value } } }))
                    .onScrollPhaseChange { _, phase in if phase == .interacting { model.editConversation { $0.followsLatest = false } } }
                    .onChange(of:chat.messages) { _, _ in if chat.followsLatest && visible { proxy.scrollTo(bottomID,anchor:.bottom) } }
                    .onChange(of:chat.id) { _, _ in if let saved = chat.readingMessageID, !chat.followsLatest { proxy.scrollTo(saved,anchor:.top) } else { proxy.scrollTo(bottomID,anchor:.bottom) } }
                    .overlay(alignment:.bottomTrailing) {
                        if !chat.followsLatest {
                            Button("Return to latest",systemImage:"arrow.down") { model.editConversation { $0.followsLatest = true }; proxy.scrollTo(bottomID,anchor:.bottom) }
                                .labelStyle(.iconOnly).rmIconButton().padding(RMLayout.pageInset).accessibilityIdentifier("chat.latest")
                        }
                    }
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                VStack(spacing:0) {
                        if let profile = model.data.providers.first(where:{ $0.id == chat.providerID }),profile.usesChatGPT,
                           AppChatGPTConfiguration.enabled,model.chatGPTSessions[profile.id]?.planUsageEnabled == true { ChatGPTUsageStrip() }
                        if model.voiceConversation { VoiceMiniView(model:model) }
                        RMComposer(text:Binding(get:{ model.data.conversations.first(where:{ $0.id == chat.id })?.draft ?? "" },set:{ value in
                            model.updateDraft(value,in:chat.id)
                        }),focus:$focus,
                            attachments:chat.attachments.map { RMAttachment(id:$0.id.uuidString,name:$0.name) },isResponding:model.running.contains(chat.id),
                            canSend:!chat.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,canStop:true,canAdd:true,canRemove:true,
                            microphone:AnyView(Button { if model.voicePhase == .listening { model.voice?.finishDictation() } else { model.startDictation() } } label: { Image(systemName:model.voicePhase == .listening ? "mic.fill" : "mic").font(.system(size:min(glyphSize,RMLayout.glyphMaximum),weight:.medium)).foregroundStyle(RMPalette.text).frame(width:RMLayout.minimumHit,height:RMLayout.minimumHit) }.accessibilityLabel("Dictate").accessibilityIdentifier("chat.dictation")),
                            onVoice:{ model.startDictation(continuous:true) },reasoningControl:AnyView(ReasoningControl(model:model,conversation:chat)),
                            onAdd:{ importer = true },onRemove:{ id in model.editConversation { $0.attachments.removeAll { $0.id.uuidString == id } } },
                            onSend:{ _,_ in
                                focus = false
                                // Without a model, sending can only fail; open the picker instead of an error.
                                if chat.providerID == nil || chat.modelID.isEmpty, !chat.draft.hasPrefix("/") { models = true } else { model.send() }
                            },onStop:{ model.stop() })
                }.background(RMPageBackground())
            }
            .onChange(of:visible) { _, value in if !value { focus = false } }
            // A hidden search field must not keep filtering the transcript.
            .onChange(of:model.chatSearchVisible) { _, shown in if !shown { query = "" } }
            .sheet(isPresented:$models) { ModelPickerView(model:model) }
            .sheet(isPresented:$repositories) { RepositoryPickerView(model:model) }
            .sheet(isPresented:$export) { BackupView(model:model,conversationOnly:true) }
            .sheet(item:$reporting) { message in
                let profile = model.data.providers.first { $0.id == (message.providerContinuation?.profileID ?? chat.providerID) }
                ReportResponseView(message:message,source:[profile?.title ?? "",message.providerContinuation?.modelID ?? chat.modelID].filter { !$0.isEmpty }.joined(separator:" · "))
            }
            .fileImporter(isPresented:$importer,allowedContentTypes:[.text,.json,.pdf,.sourceCode,.data]) { result in if case .success(let url) = result { Task { await model.importAttachment(url) } } }
        } else { ContentUnavailableView { Label("Start a conversation",systemImage:"bubble.left") } actions: { Button("New chat",action:model.newChat).rmProminentButton().frame(maxWidth:320) } }
    }
}
/// The chat's model picker, shown in the top bar like a native principal toolbar item.
struct ChatModelButton: View {
    @Bindable var model: AppModel; @State private var picking = false
    var body: some View {
        let id = model.conversation?.modelID ?? ""
        let name = model.data.providers.first(where:{ $0.id == model.conversation?.providerID })?.models.first(where:{ $0.id == id })?.displayName ?? id
        Button { picking = true } label: {
            HStack(spacing:RMLayout.unit) { Text(id.isEmpty ? "Choose model" : name).lineLimit(1).truncationMode(.middle); Image(systemName:"chevron.down").font(RMType.meta.weight(.bold)).foregroundStyle(RMPalette.secondary) }
        }
        .rmChip()
        .accessibilityLabel(id.isEmpty ? "Choose model" : "Model \(name)").accessibilityIdentifier("chat.modelPicker")
        .sheet(isPresented:$picking) { ModelPickerView(model:model) }
    }
}
/// Conversation actions, beside New chat in the top bar.
struct ChatActionsMenu: View {
    @Bindable var model: AppModel
    @State private var details = false; @State private var export = false
    var body: some View {
        if let chat = model.conversation {
            Menu {
                Picker("Persona",selection:Binding(get:{ chat.personaID },set:{ id in model.editConversation { $0.personaID = id } })) {
                    Text("Default assistant").tag(UUID?.none)
                    ForEach(model.data.personas) { Text($0.title).tag(Optional($0.id)) }
                }.pickerStyle(.menu)
                Divider()
                Button(model.chatSearchVisible ? "Hide search" : "Search conversation",systemImage:"magnifyingglass") { model.chatSearchVisible.toggle() }
                Button("Project instructions and memory",systemImage:"slider.horizontal.3") { details = true }
                Button("Encrypted export",systemImage:"square.and.arrow.up") { export = true }
                Button("Fork conversation",systemImage:"arrow.triangle.branch") { model.fork(chat.id) }
                Divider()
                Text("Context ≈ \(chat.messages.reduce(0){ $0+ContextBudget.estimate($1) }) tokens")
            } label: { Image(systemName:"ellipsis") }
                .rmIconButton().accessibilityLabel("Conversation actions").accessibilityIdentifier("chat.actions")
                .sheet(isPresented:$details) { ConversationDetailsView(model:model) }
                .sheet(isPresented:$export) { BackupView(model:model,conversationOnly:true) }
        }
    }
}
struct MessageRow: View {
    let message: ChatMessage; let streaming: Bool; let latest: Bool; let copy: () -> Void; let regenerate: () -> Void
    let follow: (String) -> Void; let read: () -> Void; let concern: () -> Void; let share: () -> Void; let review: () -> Void
    @Environment(\.displayScale) private var scale
    @State private var details = false; @State private var copied = false
    var body: some View {
        if message.role == .user {
            RMUserBubbleLayout(displayScale:scale) {
                Text(message.text).font(RMType.body).textSelection(.enabled).padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap)
                    .background(RMPalette.input,in:RoundedRectangle(cornerRadius:RMLayout.bubbleCorner,style:.continuous))
            }
        } else {
            VStack(alignment:.leading,spacing:RMLayout.rowGap) {
                if streaming && message.text.isEmpty && message.reasoning.isEmpty && message.tools.isEmpty { RMTimedActivityLabel(title:"Working…",startedAt:message.created) }
                if !message.reasoning.isEmpty { RMReasoningBlock(content:message.reasoning,isOpen:streaming && message.reasoningSeconds == nil,seconds:message.reasoningSeconds,startedAt:message.reasoningStartedAt) }
                if !message.tools.isEmpty {
                    RMToolPillStrip(events:message.tools.map { RMToolEvent(id:$0.id,title:$0.name,detail:$0.detail,status:$0.status == .failure ? .failure : $0.status == .cancelled ? .cancelled : $0.status == .running ? .running : $0.status == .approval ? .approval : .success) })
                    if message.tools.contains(where:{ $0.status == .approval }) { Button("Review pending changes",systemImage:"checkmark.shield",action:review).rmSecondaryButton().accessibilityIdentifier("chat.review") }
                }
                if streaming { RMStreamingText(content:message.text) } else if !message.text.isEmpty { RMMarkdown(message.text) }
                if !streaming {
                    HStack(spacing:0) {
                        Button(copied ? "Copied" : "Copy",systemImage:copied ? "checkmark" : "doc.on.doc") {
                            copy(); copied = true; Task { try? await Task.sleep(for:.seconds(1.5)); copied = false }
                        }.labelStyle(.iconOnly).frame(width:44,height:44).contentTransition(.symbolEffect(.replace)).sensoryFeedback(.success,trigger:copied) { _,new in new }.disabled(message.text.isEmpty)
                        Button("Read aloud",systemImage:"speaker.wave.2",action:read).labelStyle(.iconOnly).frame(width:44,height:44).disabled(message.text.isEmpty)
                        // Regenerate and follow-ups act on the latest exchange, so only the latest reply offers them.
                        if latest { Button("Regenerate",systemImage:"arrow.clockwise",action:regenerate).labelStyle(.iconOnly).frame(width:44,height:44) }
                        Menu {
                            if latest {
                                Button("Continue") { follow("Continue your previous response.") }
                                Button("Shorter") { follow("Make your previous response shorter.") }
                                Button("Formal") { follow("Rewrite your previous response in a formal tone.") }
                                Button("Explain") { follow("Explain your previous response in more detail.") }
                            }
                            Button("Encrypted share",action:share)
                            Button("Response details") { details = true }
                            if !ReportResponseView.address.isEmpty { Button("Report response…",systemImage:"flag",action:concern) }
                        } label: { Image(systemName:"ellipsis").frame(width:44,height:44) }.accessibilityLabel("More response actions")
                        Spacer()
                        if let u = message.usage { Text("\(u.input.map(String.init) ?? "?") in · \(u.output.map(String.init) ?? "?") out").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
                    }.foregroundStyle(RMPalette.secondary)
                    if let cost = message.pricing?.estimateUSD(message.usage) {
                        Text("Estimated cost \(cost,format:.currency(code:"USD").precision(.fractionLength(2...6)))")
                            .font(RMType.meta).foregroundStyle(RMPalette.secondary)
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            .sheet(isPresented:$details) {
                NavigationStack { RMForm { LabeledContent("Message",value:message.id.uuidString); LabeledContent("Finish",value:message.finishReason ?? "unknown"); LabeledContent("Created",value:message.created.formatted()); if let decision = message.reasoningDecision { LabeledContent("Reasoning",value:decision.label); Text(decision.explanation).font(RMType.meta) }; LabeledContent("Reasoning tokens",value:message.usage?.reasoning.map(String.init) ?? "unknown"); LabeledContent("Input tokens",value:message.usage?.input.map(String.init) ?? "unknown"); LabeledContent("Output tokens",value:message.usage?.output.map(String.init) ?? "unknown"); if let cost = message.pricing?.estimateUSD(message.usage) { LabeledContent("Estimated cost",value:cost.formatted(.currency(code:"USD").precision(.fractionLength(2...6)))); Text("Uses the model prices captured when this response began and reported counts across all tool rounds. Discounts, cache pricing, and destination fees may differ.").font(RMType.meta) } }.navigationTitle("Response details").toolbar { Button("Done") { details = false } } }
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
                            RMRow(profile.title,detail:ProviderMark.destination(profile),accessory:.value(profile.models.count == 1 ? "1 model" : "\(profile.models.count) models")) { ProviderMark(profile:profile) } trailing: { EmptyView() }
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
                    Button(model.data.providers.isEmpty ? "Add a provider" : "Configure providers") { model.selection = .providers; dismiss() }
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
        else { model.error = "Model IDs use letters, numbers, and - . _ / : only." }
    }
    /// Availability first; otherwise the limits and prices this app knows, never guesses.
    static func summary(_ item:ModelMetadata) -> String? {
        if let status = item.availability { return status }
        var parts:[String] = []
        if let context = item.contextTokens { parts.append("\(context.formatted(.number.notation(.compactName))) context") }
        if let input = item.inputCostPerMillion, let output = item.outputCostPerMillion {
            parts.append("$\(input.formatted(.number.precision(.fractionLength(0...2)))) / $\(output.formatted(.number.precision(.fractionLength(0...2)))) per M")
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
            return "ChatGPT plan"
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
                    Text("Your mail app opens a report to \(address) for you to review before sending. Credentials in the response are masked. \(source.isEmpty ? "" : "This response came from \(source); you can also report it to that provider.")")
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
