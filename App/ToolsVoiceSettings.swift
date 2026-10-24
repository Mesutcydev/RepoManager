import SwiftUI
import RepoManagerCore
import RepoManagerUI
import AVFoundation
import UniformTypeIdentifiers

struct ToolsView: View {
    @Bindable var model: AppModel; @State private var query = ""; @State private var tool: ToolDefinition?; @State private var macro: PromptMacro?
    @State private var importAsset = false; @State private var asset: EncryptedAsset?; @State private var releaseID = ""
    @State private var expandedGroups = Set<String>()
    var body: some View { NavigationStack {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:RMLayout.groupGap) {
                RMPageHeading(String(localized:"Tools"),detail:String(localized:"Plan mode reads. Act mode stages edits on this device. Publishing always opens a review."))
                ForEach(Array(Set(ToolCatalog.all.map(\.group))).sorted(),id:\.self) { group in
                    let definitions = ToolCatalog.all.filter { $0.group == group && !$0.nativeOnly && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.localizedDescription.localizedCaseInsensitiveContains(query)) }
                    let expanded = !query.isEmpty || expandedGroups.contains(group)
                    if !definitions.isEmpty {
                        // One card per group; the header row folds its tools away.
                        RMCard {
                            Button { if expandedGroups.contains(group) { expandedGroups.remove(group) } else { expandedGroups.insert(group) } } label: {
                                RMRow(RMLocalization.text(group),detail:definitions.count == 1 ? String(localized:"1 tool") : String(localized:"\(definitions.count) tools")) { RMIconTile(ToolsView.symbol(group)) } trailing: {
                                    Image(systemName:"chevron.forward").font(RMType.label).foregroundStyle(RMPalette.secondary)
                                        .rotationEffect(.degrees(expanded ? 90 : 0)).accessibilityHidden(true)
                                }
                            }.buttonStyle(RMPressButtonStyle()).disabled(!query.isEmpty)
                                .accessibilityValue(expanded ? String(localized:"Expanded") : String(localized:"Collapsed")).accessibilityIdentifier(group == ToolCatalog.all.first?.group ? "tools.catalog" : "tools.group.\(group)")
                            if expanded {
                                ForEach(definitions) { d in
                                    Button { tool = d } label: {
                                        RMRow(d.displayName,detail:d.localizedDescription) { Color.clear.frame(width:RMLayout.tile) } trailing: { RMBadge(d.risk == .read ? String(localized:"Read") : d.risk == .localEdit ? String(localized:"Stages") : String(localized:"Review")) }
                                    }.buttonStyle(RMPressButtonStyle()).accessibilityIdentifier("tool.\(d.name)")
                                }
                            }
                        }
                    }
                }
                RMCard(String(localized:"Prompt macros"),footer:String(localized:"Saved workflows use the same provider, scope, and review controls.")) {
                    ForEach(model.data.macros) { item in
                        Button { macro = item } label: { RMRow(item.title,detail:item.prompts.count == 1 ? String(localized:"1 step") : String(localized:"\(item.prompts.count) steps"),symbol:"text.badge.play",accessory:.chevron) }.buttonStyle(RMPressButtonStyle())
                    }
                    Button { macro = PromptMacro(title:String(localized:"New macro"),prompts:[""]) } label: { RMRow(String(localized:"Add macro"),symbol:"plus") }.buttonStyle(RMPressButtonStyle())
                }
                RMCard(String(localized:"Release assets"),footer:model.conversation?.repository == nil ? String(localized:"Select a repository in a chat to attach a release asset. Files stay encrypted on this device; maximum size is 50 MiB.") : String(localized:"Files stay encrypted on this device. Maximum size: 50 MiB per asset.")) {
                    Button { importAsset = true } label: { RMRow(String(localized:"Import release asset"),symbol:"square.and.arrow.down",accessory:.chevron) }
                        .buttonStyle(RMPressButtonStyle()).disabled(model.conversation?.repository == nil)
                    if let asset {
                        RMRow(asset.name,detail:"SHA-256 \(asset.sha256.prefix(16))…",symbol:"doc.zipper",accessory:.value(asset.byteCount.formatted(.byteCount(style:.file))))
                        HStack(spacing:RMLayout.rowGap) {
                            RMIconTile("tag")
                            TextField("Release ID",text:$releaseID).keyboardType(.numberPad).font(RMType.body)
                        }.padding(.horizontal,RMLayout.cardInset).frame(minHeight:RMLayout.rowHeight)
                    }
                }
                if asset != nil {
                    Button("Prepare upload review") { Task { _ = await model.executeTool("upload_release_asset",arguments:.object(["id":.number(Double(Int(releaseID) ?? 0)),"asset_id":.string(asset?.id.uuidString ?? "")])); model.selection = .changes } }
                        .rmProminentButton().disabled((Int(releaseID) ?? 0) <= 0 || model.conversation?.mode != .act)
                }
            }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
        }.background(RMPageBackground()).searchable(text:$query,prompt:"Search tools").navigationBarHidden(true)
        .sheet(item:$tool) { ToolFormView(model:model,definition:$0,initialArguments:.object([:])) }
        .sheet(item:$macro) { MacroEditor(model:model,initial:$0) }
        .fileImporter(isPresented:$importAsset,allowedContentTypes:[.data,.item]) { result in
            if case .success(let url) = result { Task {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do { guard let runtime = model.runtime, let owner = model.selectedConversationID else { throw RMError.forbidden }; asset = try await runtime.vault.importAsset(url,ownerID:owner) }
                catch { model.error = (error as? RMError ?? .unsupported).localizedDescription }
            } }
        }
    } }
}
extension ToolsView {
    /// Groups named after a workspace share its drawer symbol; the rest have their own.
    static func symbol(_ group:String) -> String {
        if let page = RMWorkspace.allCases.first(where:{ $0.catalogGroup == group }) { return page.symbol }
        switch group {
        case "Administration": return "gearshape"; case "Collaboration": return "person.2"
        case "General": return "doc.text.magnifyingglass"; case "Workspace": return "square.and.pencil"
        default: return "wrench.and.screwdriver"
        }
    }
}
struct MacroEditor: View {
    @Bindable var model: AppModel; let initial: PromptMacro; @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var prompt = ""
    var body: some View { NavigationStack { RMForm {
        TextField("Title",text:$title); Section("Prompts") { TextEditor(text:$prompt).frame(minHeight:200); Text("Separate steps with a line containing --- . Macros use existing provider and tool services and cannot grant approvals.").font(RMType.meta) }
        Button("Save macro") { var m = initial; m.title = String(title.prefix(100)); m.prompts = prompt.components(separatedBy:"\n---\n"); model.data.macros.removeAll { $0.id == m.id }; model.data.macros.append(m); model.save(); dismiss() }.rmProminentButton().disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        Button("Insert prompts into current chat") { model.editConversation { $0.draft = prompt }; model.selection = .chat; dismiss() }.disabled(model.conversation == nil || prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        Button("Run steps in current chat") { var m = initial; m.prompts = prompt.components(separatedBy:"\n---\n"); model.runMacro(m); dismiss() }.disabled(model.conversation == nil || model.running.contains(model.selectedConversationID ?? UUID()))
        if model.data.macros.contains(where:{ $0.id == initial.id }) { Button("Delete macro",role:.destructive) { model.data.macros.removeAll { $0.id == initial.id }; model.save(); dismiss() } }
    }.navigationTitle("Prompt macro").toolbar { Button("Done") { dismiss() } }.onAppear { title = initial.title; prompt = initial.prompts.joined(separator:"\n---\n") } } }
}
struct VoiceView: View {
    @Bindable var model: AppModel
    private var active:Bool { model.voice?.preparing == true || model.voicePhase != .idle || model.voiceConversation }
    private var hasReply:Bool { model.conversation?.messages.contains(where:{ $0.role == .assistant && !$0.text.isEmpty }) == true }
    var body: some View {
        NavigationStack { ScrollView {
            VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                RMPageHeading(String(localized:"Voice"),detail:String(localized:"Dictation and read-aloud use Apple speech on this device."))
                RMCard(footer:String(localized:"Speech recognition runs on the device with Apple system speech assets. Only the transcript reaches your selected provider. Audio is never saved. Unsupported languages are reported; the app never switches to another language or remote speech.")) {
                    RMRow(String(localized:"Session"),detail:model.voiceConversation ? String(localized:"Spoken conversation") : nil) { RMIconTile("waveform",tint:active ? RMPalette.accentText : nil) } trailing: {
                        RMBadge(model.voice?.preparing == true ? String(localized:"Preparing") : model.voicePhase.title,tint:active ? RMPalette.accentText : nil)
                    }
                    RMRow(String(localized:"Language")) { RMIconTile("globe") } trailing: {
                        TextField("Locale",text:$model.data.preferences.voiceLocale).font(RMType.body).multilineTextAlignment(.trailing)
                            .foregroundStyle(RMPalette.secondary).autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                }
                if !model.voiceTranscript.isEmpty {
                    Text(model.voiceTranscript).font(RMType.body).textSelection(.enabled).padding(RMLayout.cardInset).frame(maxWidth:.infinity,alignment:.leading).rmSurface()
                }
                VStack(spacing:RMLayout.elementGap) {
                    if model.voicePhase == .listening { Button("Finish dictation") { model.voice?.finishDictation() }.rmProminentButton() }
                    else { Button("Start dictation") { model.startDictation() }.rmProminentButton().disabled(model.voice?.preparing == true || model.voicePhase == .transcribing) }
                    Button("Start spoken conversation") { model.startDictation(continuous:true) }.rmSecondaryButton().disabled(model.conversation?.providerID == nil || model.voiceConversation)
                    if model.voicePhase == .speaking { Button("Interrupt and listen") { model.startDictation(continuous:model.voiceConversation) }.rmSecondaryButton() }
                    if active { Button("Stop voice",role:.destructive) { model.stopVoice() }.rmSecondaryButton() }
                    if model.conversation?.providerID == nil { Text("Choose a model in a chat before starting a spoken conversation.").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
                }
                RMCard(String(localized:"Read aloud")) {
                    RMRow(String(localized:"Voice")) { RMIconTile("person.wave.2") } trailing: {
                        Picker("Voice",selection:$model.data.preferences.voiceID) {
                            Text("System voice").tag(String?.none)
                            ForEach(AVSpeechSynthesisVoice.speechVoices(),id:\.identifier) { v in Text("\(v.name) · \(v.language)").tag(Optional(v.identifier)) }
                        }.labelsHidden().pickerStyle(.menu).tint(RMPalette.secondary).fixedSize()
                    }
                    HStack(spacing:RMLayout.rowGap) {
                        RMIconTile("gauge.with.needle")
                        Image(systemName:"tortoise").foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
                        Slider(value:$model.data.preferences.speechRate,in:AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate) { Text("Speech rate") }.tint(RMPalette.text)
                        Image(systemName:"hare").foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
                    }.padding(.horizontal,RMLayout.cardInset).frame(minHeight:RMLayout.rowHeight)
                    Button { if let response = model.conversation?.messages.last(where:{ $0.role == .assistant && !$0.text.isEmpty }) { model.voice?.speak(response.text,voiceID:model.data.preferences.voiceID,rate:model.data.preferences.speechRate) } } label: {
                        RMRow(String(localized:"Read latest response"),symbol:"speaker.wave.2")
                    }.buttonStyle(RMPressButtonStyle()).disabled(model.voice?.preparing == true || !hasReply || model.voicePhase == .listening)
                }
            }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
        }.background(RMPageBackground()).navigationTitle("Voice").navigationBarHidden(true).onChange(of:model.data.preferences) { _, _ in model.save() } }
    }
}
struct VoiceMiniView: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing:RMLayout.rowGap) {
            Image(systemName:"waveform"); Text(model.voicePhase.title).font(RMType.meta)
            Spacer()
            Button("Open voice") { model.selection = .voice }.rmTextButton()
            Button("Stop voice",systemImage:"stop.fill") { model.stopVoice() }.labelStyle(.iconOnly).rmIconButton()
        }.padding(.horizontal,RMLayout.cardInset).background(.regularMaterial).accessibilityIdentifier("voice.minimized")
    }
}
struct SettingsView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var backup = false; @State private var confirmWipe = false; @State private var personas = false
    var body: some View {
        NavigationStack { RMForm {
            Section {
                Picker("Appearance",systemImage:"circle.lefthalf.filled",selection:$model.data.preferences.appearance) { ForEach(RMAppearancePreference.allCases) { Text($0.title).tag($0.rawValue) } }
                Button("Replay onboarding",systemImage:"arrow.counterclockwise") { model.data.preferences.onboardingCompleted = false; model.save(); dismiss() }
            }
            Section {
                Toggle("Encrypted iCloud sync",systemImage:"icloud",isOn:$model.data.preferences.syncHistory)
                Button("Sync now",systemImage:"arrow.triangle.2.circlepath") { Task { await model.synchronize() } }.disabled(!model.data.preferences.syncHistory)
                if model.data.preferences.syncHistory,let message = model.syncError {
                    RMInlineNotice(title:"iCloud sync paused",detail:message,symbol:"icloud.slash",isError:true)
                }
                Button("Encrypted backup and restore",systemImage:"externaldrive") { backup = true }
                Button("Custom personas",systemImage:"person.2") { personas = true }
            } header: { Text("History") } footer: {
                Text("Opt-in sync uploads encrypted history to your private CloudKit database. Its separate key uses Apple's end-to-end encrypted Keychain sync. Credentials, repository drafts, caches, reviews and client grants stay on this device.")
            }
            Section {
                Toggle("Background refresh",systemImage:"arrow.clockwise",isOn:Binding(get:{ model.data.preferences.backgroundNetworkRefresh == true },set:{ model.data.preferences.backgroundNetworkRefresh = $0 }))
            } footer: {
                Text("Refreshes repository activity and encrypted history. iOS schedules short, bounded refreshes. Refresh waits while Keychain is locked. AI runs, reviews, voice and the API listener require the app to be active.")
            }
            Section {
                Toggle("Web access",systemImage:"globe",isOn:$model.data.preferences.webEnabled)
                Picker("Search provider",systemImage:"magnifyingglass",selection:$model.data.preferences.webProvider) { Text("Direct HTTPS URLs").tag("direct"); Text("DuckDuckGo (experimental)").tag("duckduckgo"); Text("Brave").tag("brave"); Text("Tavily").tag("tavily"); Text("Exa").tag("exa"); Text("SearXNG").tag("searxng"); Text("Custom").tag("custom") }
                TextField("HTTPS search endpoint",text:$model.data.preferences.webEndpoint).autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                NavigationLink { WebCredentialView(model:model) } label: { Label("Credential and consent",systemImage:"key") }
            } header: { Text("Web") } footer: {
                Text("Web requests share your query with the configured service. Direct fetches contact the public HTTPS destination requested by the tool. Sources are treated as untrusted content.")
            }
            Section {
                Button("Wipe Repo Manager data",systemImage:"trash",role:.destructive) { confirmWipe = true }
            } header: { Text("Privacy") } footer: {
                Text("Sensitive records are encrypted using AES-256-GCM. API tokens and device keys are held in Keychain. No plaintext fallback, telemetry, camera, or imported model runtime is included. Copy uses a device-local clipboard with a 60-second expiry. Local wipe preserves the shared history key and encrypted iCloud history, and requires device-owner authentication.")
            }
            Section {
                NavigationLink {
                    ScrollView { Text((Bundle.main.url(forResource:"ThirdPartyNotices",withExtension:"txt").flatMap { try? String(contentsOf:$0,encoding:.utf8) }) ?? String(localized:"Notices are unavailable.")).font(RMType.meta).textSelection(.enabled).padding(RMLayout.pageInset).frame(maxWidth:760,alignment:.leading).frame(maxWidth:.infinity) }.background(RMPageBackground()).navigationTitle("Licenses")
                } label: { Label("Licenses and notices",systemImage:"doc.text") }
            } footer: {
                Text("Repo Manager adapts MIT-licensed OnDeviceMax UI components by Mesut and iOS Local LLM contributors. Swift-Sodium 0.11.0 is ISC-licensed.")
            }
        }.navigationTitle("Settings").toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { model.save(); dismiss() } } }
        .onChange(of:model.data.preferences) { old, new in
            if old.webEndpoint != new.webEndpoint || old.webProvider != new.webProvider {
                model.data.preferences.webConsentEndpoint = nil
                do { try model.runtime?.credentials.delete("web-search") }
                catch { model.data.preferences.webEnabled = false; model.error = RMError.locked.localizedDescription }
            }
            model.save(); Task { await model.runtime?.web.configure(model.data.preferences) }
            if old.backgroundNetworkRefresh != new.backgroundNetworkRefresh || old.syncHistory != new.syncHistory {
                BackgroundNetworking.shared.schedule(enabled:new.backgroundNetworkRefresh == true,sync:new.syncHistory)
            }
        }
        .sheet(isPresented:$backup) { BackupView(model:model,conversationOnly:false) }
        .sheet(isPresented:$personas) { PersonasView(model:model) }
        .confirmationDialog("Permanently remove this app's encrypted records and Keychain items?",isPresented:$confirmWipe,titleVisibility:.visible) {
            Button("Wipe Repo Manager",role:.destructive) { Task { do { try await model.wipe(); dismiss() } catch { model.error = (error as? RMError ?? .locked).localizedDescription } } }
        }
        }
    }
}
struct WebCredentialView: View {
    @Bindable var model: AppModel; @State private var credential = ""; @State private var consent = false
    @State private var allowedHosts = ""
    var body: some View {
        RMForm {
            SecureField("Search API credential",text:$credential).privacySensitive().autocorrectionDisabled().textInputAutocapitalization(.never)
            Text(model.data.preferences.webProvider == "direct" ? String(localized:"Allow tools to fetch public HTTPS pages from the exact hosts below. URLs in repository text cannot grant access to other hosts.") : String(localized:"Search destination: \(model.data.preferences.webEndpoint)"))
            TextField("Allowed fetch hosts, one per line",text:$allowedHosts,axis:.vertical).autocorrectionDisabled().textInputAutocapitalization(.never)
            Toggle("Allow configured web destination",isOn:$consent)
            Button("Save securely") { Task { do {
                if model.data.preferences.webProvider != "direct" { guard let url = URL(string:model.data.preferences.webEndpoint) else { throw RMError.invalidInput }; try URLPolicy.validate(url) }
                let hosts = allowedHosts.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
                guard hosts.count <= 30 else { throw RMError.tooLarge }
                for host in hosts { guard let url = URL(string:"https://"+host),url.host == host,url.path.isEmpty,url.query == nil else { throw RMError.invalidInput }; try URLPolicy.validate(url) }
                model.data.preferences.webAllowedHosts = Array(Set(hosts)).sorted()
                if !credential.isEmpty {
                    guard !model.locked,let runtime = model.runtime,credential.utf8.count <= 2048 else { throw RMError.locked }
                    let record = WebSearchCredential(key:credential,provider:model.data.preferences.webProvider,endpoint:model.data.preferences.webEndpoint)
                    try runtime.credentials.write(JSONEncoder().encode(record),account:"web-search"); credential = ""
                }
                model.data.preferences.webConsentEndpoint = consent ? (model.data.preferences.webProvider == "direct" ? "public-https" : model.data.preferences.webEndpoint) : nil
                await model.runtime?.web.configure(model.data.preferences); await model.flush()
            } catch { model.error = (error as? RMError ?? .locked).localizedDescription } } }
        }.navigationTitle("Web privacy").onAppear { allowedHosts = (model.data.preferences.webAllowedHosts ?? []).joined(separator:"\n"); consent = model.data.preferences.webConsentEndpoint != nil }.onDisappear { credential = "" }
    }
}
struct PersonasView: View {
    @Bindable var model: AppModel; @State private var editor: Persona?
    var body: some View { NavigationStack { List {
        Button("Add persona") { editor = Persona(title:String(localized:"New persona"),instruction:"") }
        ForEach(model.data.personas) { persona in Button(persona.title) { editor = persona } }
    }.navigationTitle("Personas").sheet(item:$editor) { PersonaEditor(model:model,initial:$0) } } }
}
struct PersonaEditor: View {
    @Bindable var model: AppModel; let initial: Persona; @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var instruction = ""
    var body: some View { NavigationStack { RMForm {
        TextField("Title",text:$title); TextEditor(text:$instruction).frame(minHeight:200)
        Button("Save persona") { var p = initial; p.title = String(title.prefix(100)); p.instruction = String(instruction.prefix(8192)); model.data.personas.removeAll { $0.id == p.id }; model.data.personas.append(p); model.save(); dismiss() }.rmProminentButton().disabled(title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || instruction.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        if model.data.personas.contains(where:{ $0.id == initial.id }) { Button("Delete persona",role:.destructive) { model.data.personas.removeAll { $0.id == initial.id }; model.save(); dismiss() } }
    }.navigationTitle("Persona").onAppear { title = initial.title; instruction = initial.instruction }.toolbar { Button("Cancel") { dismiss() } } } }
}
extension UTType { static let repoManagerBundle = UTType(exportedAs:"com.mesutcydev.repomanager.encrypted-bundle",conformingTo:.data) }
struct EncryptedDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.repoManagerBundle,.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { guard let value = configuration.file.regularFileContents else { throw RMError.corruptRecord }; data = value }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct BackupView: View {
    @Bindable var model: AppModel; let conversationOnly: Bool; @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""; @State private var exporting = false; @State private var importing = false
    @State private var document: EncryptedDocument?; @State private var busy = false
    var body: some View { NavigationStack { RMForm {
        Text("This bundle is authenticated and encrypted with an Argon2id-derived key. Use a strong passphrase of at least 12 characters. Credentials and live approvals are excluded.")
        SecureField("Bundle passphrase",text:$passphrase).privacySensitive().textInputAutocapitalization(.never).autocorrectionDisabled()
        Button(conversationOnly ? String(localized:"Export this conversation encrypted") : String(localized:"Export encrypted backup")) { create() }.rmProminentButton().disabled(busy || passphrase.count < 12)
        if !conversationOnly { Button("Import encrypted backup") { importing = true }.rmSecondaryButton().disabled(busy || passphrase.isEmpty) }
        if busy { ProgressView("Preparing encrypted bundle…") }
        Text("Imported drafts require explicit repository reconnection and a new native review before publication.").font(RMType.meta)
    }.navigationTitle("Encrypted bundle").toolbar { Button("Done") { passphrase = ""; dismiss() } }
    .fileExporter(isPresented:$exporting,document:document,contentType:.repoManagerBundle,defaultFilename:"RepoManager.rmbundle") { _ in document = nil; passphrase = "" }
    .fileImporter(isPresented:$importing,allowedContentTypes:[.repoManagerBundle,.data]) { result in if case .success(let url) = result { restore(url) } }
    .onDisappear { passphrase = ""; document = nil }
    } }
    private func create() {
        busy = true
        Task {
            do {
                var data = model.data
                if conversationOnly { data.conversations = model.conversation.map { [$0] } ?? []; data.accounts = []; data.providers = []; data.preferences = AppPreferences(); data.macros = []; data.tombstones = [:] }
                let drafts = conversationOnly ? [] : await model.runtime?.workspace.allDrafts() ?? []
                let checkpoints = conversationOnly ? [] : await model.runtime?.workspace.allCheckpoints() ?? []
                let payload = BackupPayload(data:data,drafts:drafts,checkpoints:checkpoints); let phrase = passphrase
                let encrypted = try await Task.detached { try EncryptedBackup.export(payload,passphrase:phrase) }.value
                document = EncryptedDocument(data:encrypted); exporting = true
            } catch { model.error = (error as? RMError ?? .unavailable).localizedDescription }; busy = false
        }
    }
    private func restore(_ url: URL) {
        busy = true
        Task {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 90*1024*1024 else { throw RMError.tooLarge }
                let bytes = try BoundedFile.read(url,limit:90*1024*1024), phrase = passphrase
                let lease = model.lifecycleID; guard let runtime = model.runtime,!model.locked else { throw RMError.locked }
                let payload = try await Task.detached { BackupImport.prepare(try EncryptedBackup.restore(bytes,passphrase:phrase)) }.value
                try Task.checkCancellation(); guard !model.locked,model.lifecycleID == lease else { throw RMError.cancelled }
                try await runtime.workspace.importDrafts(payload.drafts,checkpoints:payload.checkpoints)
                guard !model.locked,model.lifecycleID == lease else { throw RMError.cancelled }
                model.data.conversations += payload.data.conversations
                model.data.providers += payload.data.providers; model.data.personas += payload.data.personas; model.data.macros += payload.data.macros
                await model.flush(); await model.refreshWorkspace(); passphrase = ""; dismiss()
            } catch { model.error = (error as? RMError ?? .corruptRecord).localizedDescription }; busy = false
        }
    }
}
