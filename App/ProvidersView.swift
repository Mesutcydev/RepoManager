import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct ProvidersView: View {
    @Bindable var model: AppModel
    @State private var editor: ProviderProfile?; @State private var comparing = false; @State private var choosing = false
    @State private var removing: ProviderProfile?
    @State private var refreshing = Set<UUID>()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    RMPageHeading("Providers",detail:"Each chat uses one provider and model. Credentials stay in Keychain.") {
                        Button { choosing = true } label: { Image(systemName:"plus") }.rmIconButton().accessibilityLabel("Add provider")
                    }
                    if model.data.providers.isEmpty {
                        let detail: LocalizedStringKey = AppChatGPTConfiguration.enabled
                            ? "Use your ChatGPT plan, Apple Intelligence, a provider’s API key, or your own HTTPS endpoint. You approve where your conversations go."
                            : "Use Apple Intelligence, a provider’s API key, or your own HTTPS endpoint. You approve where your conversations go."
                        RMEmptyState("Choose how you want to work",detail:detail,symbol:"point.3.connected.trianglepath.dotted")
                        Button("Add provider") { choosing = true }.rmProminentButton()
                    }
                    ForEach(model.data.providers) { profile in
                        let allowed = profile.consentEndpoint == profile.endpoint
                        let connected = model.chatGPTSessions[profile.id]?.planUsageEnabled == true
                        RMCard(dividerInset:RMLayout.cardInset) {
                            Button { editor = profile } label: {
                                RMRow(profile.title,detail:ProviderMark.destination(profile),accessory:.chevron) { ProviderMark(profile:profile) } trailing: { EmptyView() }
                            }.buttonStyle(RMPressButtonStyle()).accessibilityHint("Edit profile")
                            // Status line: consent and catalog size, then the card's two actions.
                            HStack(spacing:RMLayout.rowGap) {
                                Label(profile.usesChatGPT ? (connected ? "Using ChatGPT plan" : "Sign-in needed") : (allowed ? "Allowed" : "Consent needed"),systemImage:allowed && (!profile.usesChatGPT || connected) ? "checkmark.shield.fill" : "exclamationmark.circle")
                                    .foregroundStyle(allowed ? RMPalette.accentText : RMPalette.secondary)
                                Text(profile.models.count == 1 ? "1 model" : "\(profile.models.count) models").foregroundStyle(RMPalette.secondary)
                                Spacer(minLength:0)
                                Button { refresh(profile) } label: {
                                    if refreshing.contains(profile.id) { ProgressView().controlSize(.small) } else { Image(systemName:"arrow.clockwise") }
                                }.disabled(refreshing.contains(profile.id) || !allowed || (profile.usesChatGPT && !connected))
                                    .accessibilityLabel("Refresh catalog for \(profile.title)")
                                Menu { Button("Remove provider",systemImage:"trash",role:.destructive) { removing = profile } } label: { Image(systemName:"ellipsis") }
                                    .accessibilityLabel("Actions for \(profile.title)")
                            }
                            .font(RMType.label).labelStyle(RMCompactLabelStyle())
                            .buttonStyle(RMInlineIconButtonStyle())
                            .padding(.leading,RMLayout.cardInset).padding(.trailing,RMLayout.cardInset - RMLayout.inlineIconOutset)
                            .frame(minHeight:RMLayout.controlLarge)
                        }
                    }
                    if !model.data.providers.isEmpty {
                        RMCard {
                            Button { comparing = true } label: { RMRow("Compare providers",detail:"Run one prompt across providers and see time, usage, and cost.",symbol:"chart.bar",accessory:.chevron) }
                                .buttonStyle(RMPressButtonStyle())
                        }
                    }
                }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).navigationBarHidden(true)
            .sheet(item:$editor) { profile in
                if profile.usesChatGPT { ChatGPTAccountView(model:model,initial:profile) }
                else { ProviderEditor(model:model,initial:profile) }
            }
            .sheet(isPresented:$choosing) { ProviderPresetChooser(model:model) }
            .confirmationDialog("Remove “\(removing?.title ?? "")”?",isPresented:Binding(get:{ removing != nil },set:{ if !$0 { removing = nil } }),titleVisibility:.visible,presenting:removing) { profile in
                Button("Remove provider",role:.destructive) { Task { do { try await model.deleteProvider(profile.id) } catch { model.error = RMError.locked.localizedDescription } } }
            } message: { _ in Text("Its saved credential is deleted from Keychain. Conversations using it will need another model.") }
            .sheet(isPresented:$comparing) { ProviderComparisonView(model:model) }
        }
    }
    private func refresh(_ profile:ProviderProfile) {
        guard refreshing.insert(profile.id).inserted else { return }
        let lease = model.lifecycleID
        Task {
            defer { refreshing.remove(profile.id) }
            do { try await model.refreshCatalog(profile.id) }
            catch { if !model.locked,model.lifecycleID == lease { model.showProviderError(error) } }
        }
    }
}
struct ProviderPresetChooser: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""; @State private var editor: ProviderProfile?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    if AppChatGPTConfiguration.enabled,query.isEmpty || "ChatGPT".localizedCaseInsensitiveContains(query) {
                        RMCard("Use your ChatGPT plan") {
                            Button {
                                var profile = ProviderProfile(preset:.openAI,title:"ChatGPT"); profile.authentication = .chatGPT
                                editor = profile
                            } label: {
                                RMRow("ChatGPT",detail:"Connect an eligible Plus or Pro account",symbol:"person.crop.circle",accessory:.chevron)
                            }.buttonStyle(RMPressButtonStyle()).accessibilityIdentifier("provider.chatgpt")
                        }
                    }
                    let presets = ProviderPreset.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    ForEach(PresetGroup.allCases,id:\.self) { group in
                        let members = presets.filter { group.contains($0) }
                        if !members.isEmpty {
                            RMCard(group.title) {
                                ForEach(members) { preset in
                                    Button { editor = ProviderProfile(preset:preset) } label: {
                                        RMRow(preset.title,detail:group.detail(preset),accessory:.chevron) { ProviderMark(preset:preset) } trailing: { EmptyView() }
                                    }.buttonStyle(RMPressButtonStyle()).accessibilityLabel(preset.title).accessibilityIdentifier("provider.preset.\(preset.id)")
                                }
                            }
                        }
                    }
                    if presets.isEmpty {
                        RMEmptyState("No matching providers",detail:"Try another name, or clear the search to choose a custom endpoint.",symbol:"magnifyingglass")
                    }
                }.padding(RMLayout.pageInset).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).searchable(text:$query,prompt:"Find a provider")
                .navigationTitle("Add provider").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() } } }
                .sheet(item:$editor) { profile in
                    if profile.usesChatGPT { ChatGPTAccountView(model:model,initial:profile) }
                    else { ProviderEditor(model:model,initial:profile) }
                }
        }
    }
}
/// Presets grouped by where requests go: this device, a hosted API, or your own server.
private enum PresetGroup: CaseIterable {
    case apple, hosted, custom
    var title: String { switch self { case .apple: "On this device"; case .hosted: "Hosted APIs"; case .custom: "Your endpoint" } }
    func contains(_ preset:ProviderPreset) -> Bool {
        switch self { case .apple: preset == .apple; case .custom: preset == .custom; case .hosted: preset != .apple && preset != .custom }
    }
    func detail(_ preset:ProviderPreset) -> String {
        switch self {
        case .apple: "On device or Private Cloud Compute"
        case .custom: "Any OpenAI-compatible HTTPS endpoint"
        case .hosted: URL(string:preset.endpoint)?.host ?? "Use your API key"
        }
    }
}
/// Plain 44-pt icon targets for actions inside a card, where glass would stack on glass.
struct RMInlineIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(RMType.body.weight(.medium))
            .foregroundStyle(isEnabled ? RMPalette.text : RMPalette.secondary)
            .frame(width:RMLayout.minimumHit,height:RMLayout.minimumHit).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
struct ProviderEditor: View {
    @Bindable var model: AppModel; let initial: ProviderProfile
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var endpoint = ""; @State private var format = WireFormat.chatCompletions
    @State private var key = ""; @State private var consent = false; @State private var bridge = false
    @State private var manual = ""; @State private var saving = false
    @State private var models:[ModelMetadata] = []
    var body: some View {
        NavigationStack {
            RMForm {
                if initial.preset == .apple {
                    Section("Apple Intelligence") {
                        TextField("Name",text:$title)
                        Text("Apple manages the system models. No API credential or model download is needed. Private Cloud Compute requires OS 27 and this app's signed entitlement; the on-device option uses the installed Apple system model.")
                    }
                    Section("Your content") {
                        Text("Selecting Private Cloud Compute sends the conversation, attached text, and explicitly retrieved repository context to Apple's private inference service. Selecting On Device processes model input on this device. Repository and web tools retain their own network permissions.")
                        Toggle("Allow Apple model requests",isOn:$consent)
                    }
                } else {
                Section("Provider profile") {
                    TextField("Name",text:$title)
                    TextField("HTTPS endpoint",text:$endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Picker("Protocol",selection:$format) { ForEach(WireFormat.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                    SecureField("API credential (Keychain only)",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Text("Leave the credential empty to retain it for the same endpoint. Changing the endpoint removes the saved credential.").font(RMType.meta)
                }
                Section {
                    Text("Requests send conversation text, explicitly attached documents, and selected repository context to this HTTPS destination. Provider retention policies apply. Catalog refresh sends your API credential.")
                    Text(endpoint).font(RMType.meta).textSelection(.enabled)
                    Toggle("Allow requests to this destination",isOn:$consent)
                } header: { Text("Destination disclosure") } footer: { if !consent { Text("Allow requests to this destination to save.") } }
                Section("Models and tools") {
                    TextField("Add manual model ID",text:$manual).textInputAutocapitalization(.never).autocorrectionDisabled()
                    ForEach($models) { metadata in NavigationLink(metadata.wrappedValue.id) { ModelConfigurationView(metadata:metadata,profile:initial) } }
                    Toggle("Explicit text-tool compatibility",isOn:$bridge)
                    Text("Use native tool calls when available. Compatibility mode accepts only a complete dedicated tool block, outside reasoning or quoted examples.").font(RMType.meta)
                }
                }
                if saving { ProgressView("Saving provider…") }
            }.navigationTitle(initial.preset == .apple ? "Apple Intelligence" : "Provider settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { key = ""; dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Save") { save() }.disabled(saving || !consent || !validEndpoint || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
            }
            .onAppear { if title.isEmpty { title = initial.title; endpoint = initial.endpoint; format = initial.format; consent = initial.consentEndpoint == initial.endpoint; bridge = initial.textToolBridge; models = initial.models } }
            .onChange(of:endpoint) { old, new in if !old.isEmpty, old != new { consent = false } }
            .onDisappear { key = "" }
        }
    }
    private var validEndpoint:Bool {
        if initial.preset == .apple { return true }
        guard let url = URL(string:endpoint.trimmingCharacters(in:.whitespacesAndNewlines)) else { return false }
        return (try? URLPolicy.validate(url)) != nil
    }
    private func save() {
        saving = true
        Task {
            do {
                var profile = initial; profile.title = title; profile.endpoint = endpoint.trimmingCharacters(in:.whitespaces); profile.format = format
                profile.consentEndpoint = consent ? profile.endpoint : nil; profile.textToolBridge = bridge; profile.models = models
                if profile.preset == .apple { profile.models = await model.runtime?.providers.apple.catalog() ?? [] }
                else if !manual.isEmpty { let id = try InputValidation.model(manual); if !profile.models.contains(where:{ $0.id == id }) { profile.models.append(ModelMetadata(id:id)) } }
                try await model.upsertProvider(profile,credential:key); key = ""; dismiss()
            } catch { model.error = (error as? RMError ?? .invalidInput).localizedDescription }
            saving = false
        }
    }
}
struct ProviderComparisonView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var prompt = "Explain a safe GitHub pull request review workflow in five steps."
    @State private var selected = Set<UUID>(); @State private var results: [UUID:String] = [:]
    @State private var active = false; @State private var task: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            RMForm {
                Section("Explicit benchmark prompt") { TextEditor(text:$prompt).frame(minHeight:100); Text("Each selected provider receives a request to its first catalog model. ChatGPT uses your plan; API-key providers bill API usage. Tools and repository context are disabled. Missing usage or prices remain unknown.").font(RMType.meta) }
                ForEach(model.data.providers.filter { !$0.models.isEmpty }) { profile in
                    Section(profile.title) {
                        Toggle(profile.models.first?.id ?? "",isOn:Binding(get:{ selected.contains(profile.id) },set:{ if $0 { selected.insert(profile.id) } else { selected.remove(profile.id) } }))
                        if let result = results[profile.id] { Text(result).font(RMType.meta).textSelection(.enabled) }
                    }
                }
                Button(active ? "Stop comparison" : "Run selected comparisons") { if active { task?.cancel() } else { compare() } }
                    .rmProminentButton().disabled(!active && (selected.isEmpty || prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty))
                if active { ProgressView("Comparing providers…") }
            }.navigationTitle("Provider comparison").toolbar { Button("Done") { task?.cancel(); dismiss() } }
        }.onDisappear { task?.cancel() }
        .onChange(of:model.locked) { _,locked in if locked { task?.cancel() } }
        .onChange(of:model.data.providers) { _,_ in task?.cancel() }
    }
    private func compare() {
        active = true; results = [:]
        let profiles = model.data.providers.filter { selected.contains($0.id) }
        let comparisonPrompt = prompt, lifecycle = model.lifecycleID
        task = Task {
            guard let runtime = model.runtime else { active = false; return }
            for profile in profiles {
                if Task.isCancelled { break }; guard let item = profile.models.first else { continue }
                guard !model.locked,model.lifecycleID == lifecycle else { break }
                let started = Date(); var text = ""; var reported = RunUsage(); var usage: Usage?
                var request = RunRequest(conversationID:UUID(),profile:profile,model:item.id,messages:[ChatMessage(role:.user,text:comparisonPrompt)])
                request.executeTools = false
                do { for try await event in runtime.providers.stream(request) {
                        try Task.checkCancellation(); guard !model.locked,model.lifecycleID == lifecycle else { throw RMError.cancelled }
                        switch event { case .text(let t): text += t; guard text.utf8.count <= 1024*1024 else { throw RMError.tooLarge }; case .usage(let u): usage = try reported.update(u); default: break }
                    }
                    try Task.checkCancellation(); guard !model.locked,model.lifecycleID == lifecycle else { throw RMError.cancelled }; usage = reported.finishRound()
                    var result = text+"\n\nElapsed: \(Date().timeIntervalSince(started).formatted(.number.precision(.fractionLength(2)))) s\nUsage: \(usage?.input.map(String.init) ?? "unknown") in, \(usage?.output.map(String.init) ?? "unknown") out"
                    if let cost = MessagePricing(metadata:item,format:ProviderRouting.format(profile:profile,model:item.id))?.estimateUSD(usage) { result += "\nEstimated cost: \(cost.formatted(.currency(code:"USD").precision(.fractionLength(2...6))))" }
                    results[profile.id] = result
                } catch { if !model.locked,model.lifecycleID == lifecycle { results[profile.id] = ProviderFailure.safe(error).localizedDescription; if (error as? ChatGPTServiceError)?.requiresUsageManagement == true { model.showProviderError(error) } } }
            }
            active = false
        }
    }
}
