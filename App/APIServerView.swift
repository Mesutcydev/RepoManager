import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct APIServerView: View {
    @Bindable var model: AppModel; @State private var pairing = false; @State private var exportCertificate = false
    @State private var document: EncryptedDocument?
    @State private var changingServer = false
    var body: some View { NavigationStack { ScrollView {
        VStack(alignment:.leading,spacing:RMLayout.groupGap) {
            RMPageHeading(String(localized:"API server"),detail:String(localized:"Let external agents use your providers and repository tools through scoped grants."))
            RMCard(footer:String(localized:"The listener is opt-in. Clients authenticate with individual Keychain credentials and receive explicit provider, repository and tool grants. API requests can never approve a native review.")) {
                RMRow(String(localized:"HTTPS listener"),detail:model.serverRunning ? String(localized:"Listening on port 11435") : String(localized:"Port 11435")) { RMIconTile("network",tint:model.serverRunning ? RMPalette.accentText : nil) } trailing: {
                    RMBadge(model.serverRunning ? String(localized:"On") : String(localized:"Off"),tint:model.serverRunning ? RMPalette.accentText : nil)
                }
                RMRow(String(localized:"Host")) { RMIconTile("server.rack") } trailing: {
                    TextField("Hostname or IPv4 address",text:$model.data.preferences.serverHost).font(RMType.body).multilineTextAlignment(.trailing)
                        .foregroundStyle(RMPalette.secondary).autocorrectionDisabled().textInputAutocapitalization(.never).disabled(model.serverRunning)
                }
            }
            Group {
                if model.serverRunning { Button("Stop server",role:.destructive,action:toggleServer).rmSecondaryButton() }
                else { Button("Start server",action:toggleServer).rmProminentButton() }
            }.disabled(changingServer || model.data.preferences.serverHost.isEmpty)
            if let certificate = model.certificate {
                RMCard(String(localized:"Public TLS trust"),footer:String(localized:"Verify the fingerprint in person and trust the public certificate on the client. It validates this configured hostname or IP. Never disable certificate verification.")) {
                    RMRow(String(localized:"Address"),detail:"https://\(model.data.preferences.serverHost):11435",symbol:"link")
                    HStack(alignment:.top,spacing:RMLayout.rowGap) {
                        RMIconTile("lock.shield")
                        VStack(alignment:.leading,spacing:2) {
                            Text("SHA-256 fingerprint").font(RMType.rowTitle).foregroundStyle(RMPalette.text)
                            Text(model.fingerprint).font(.system(.footnote,design:.monospaced)).foregroundStyle(RMPalette.secondary).textSelection(.enabled)
                        }
                    }.padding(RMLayout.cardInset).frame(maxWidth:.infinity,alignment:.leading)
                    Button { document = EncryptedDocument(data:Data(TLSIdentity.pem(certificate).utf8)); exportCertificate = true } label: {
                        RMRow(String(localized:"Export public certificate"),symbol:"square.and.arrow.up")
                    }.buttonStyle(RMPressButtonStyle())
                }
            }
            RMCard(String(localized:"Clients")) {
                Button { pairing = true } label: { RMRow(String(localized:"Pair scoped client"),detail:model.serverRunning ? nil : String(localized:"Start the server first"),symbol:"link") }
                    .buttonStyle(RMPressButtonStyle()).disabled(!model.serverRunning)
                ForEach(model.clients) { client in
                    RMRow(client.name,detail:client.revoked ? String(localized:"Revoked") : client.repository?.fullName ?? String(localized:"No repository grant")) { RMIconTile("person.badge.key") } trailing: {
                        Button("Revoke",role:.destructive) { Task { do { try await model.runtime?.api.revokeClient(client.id); model.clients = await model.runtime?.authorization.clients() ?? [] } catch { model.error = RMError.locked.localizedDescription } } }
                            .rmChip().disabled(client.revoked)
                    }
                }
            }
            Text("Compatible with OpenAI Chat Completions and Responses, Anthropic Messages, Ollama text routes, and versioned agent sessions, runs and tools. No images, audio, embeddings, classifier, existing-chat access, or local runtime.")
                .font(RMType.meta).foregroundStyle(RMPalette.secondary).padding(.horizontal,RMLayout.cardInset)
            if changingServer { ProgressView("Updating server…").frame(maxWidth:.infinity) }
        }.padding(RMLayout.pageInset).frame(maxWidth:680,alignment:.leading).frame(maxWidth:.infinity)
    }.background(RMPageBackground()).navigationTitle("API server").navigationBarHidden(true)
    .sheet(isPresented:$pairing) { ClientPairingView(model:model) }
    .fileExporter(isPresented:$exportCertificate,document:document,contentType:.data,defaultFilename:"RepoManager-public-certificate.crt") { _ in document = nil }
    } }
    private func toggleServer() {
        changingServer = true
        Task {
            defer { changingServer = false }
            do { if model.serverRunning { await model.stopServer() } else { try await model.startServer() }; model.save() }
            catch { model.error = (error as? RMError ?? .connection).localizedDescription }
        }
    }
}
struct ClientPairingView: View {
    @Bindable var model: AppModel; @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var selected = Set<UUID>(); @State private var repository = false
    @State private var tools = Set<String>(); @State private var reveal = false; @State private var busy = false
    var body: some View {
        NavigationStack { RMForm {
            TextField("Client name",text:$name)
            Section("Provider grants") { ForEach(model.data.providers) { profile in Toggle(profile.title,isOn:Binding(get:{ selected.contains(profile.id) },set:{ if $0 { selected.insert(profile.id) } else { selected.remove(profile.id) } })) } }
            Section("Repository grant") { Toggle("Grant selected repository",isOn:$repository).disabled(model.conversation?.repository == nil); Text(model.conversation?.repository?.fullName ?? String(localized:"None selected")).font(RMType.meta) }
            Section("Tool grants") {
                Text("Only the selected repository is granted. Repository creation, forking, and secret entry remain in the native app.").font(RMType.meta)
                ForEach(ToolCatalog.all.filter(ExternalToolPolicy.permits)) { d in Toggle(d.name,isOn:Binding(get:{ tools.contains(d.name) },set:{ if $0 { tools.insert(d.name) } else { tools.remove(d.name) } })) }
            }
            Button("Create scoped credential") { create() }.rmProminentButton().disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || selected.isEmpty || model.oneTimeCredential != nil)
            if busy { ProgressView("Creating scoped client…") }
            if let credential = model.oneTimeCredential {
                Section("One-time credential") {
                    Text("Enter this credential directly in the client, or securely pair on the same trusted network. It is never exported or copied. Closing this sheet removes it from the display.").font(RMType.meta)
                    if reveal { Text(credential).font(.system(.caption,design:.monospaced)).privacySensitive() }
                    else { SecureField("Credential",text:.constant(credential)).disabled(true).privacySensitive() }
                    Button(reveal ? String(localized:"Hide") : String(localized:"Reveal once")) { reveal.toggle() }
                }
            }
        }.navigationTitle("Pair agent client").toolbar { Button("Done") { model.oneTimeCredential = nil; dismiss() } }.onDisappear { model.oneTimeCredential = nil }
        }
    }
    private func create() {
        guard !model.locked,model.serverRunning,let runtime = model.runtime else { return }
        let lease = model.lifecycleID,scope = model.conversation?.repository,cid = model.selectedConversationID
        let grant = APIClientGrant(name:name,providerIDs:selected,repository:repository ? scope : nil,tools:tools)
        busy = true
        Task {
            defer { busy = false }
            do {
                let credential = try await runtime.authorization.create(grant)
                guard !Task.isCancelled,!model.locked,model.serverRunning,model.lifecycleID == lease,model.selectedConversationID == cid,model.conversation?.repository == scope else {
                    try await runtime.api.revokeClient(grant.id); return
                }
                let clients = await runtime.authorization.clients()
                guard !model.locked,model.lifecycleID == lease else { try await runtime.api.revokeClient(grant.id); return }
                model.oneTimeCredential = credential; model.clients = clients
            } catch { if !model.locked,model.lifecycleID == lease { model.error = (error as? RMError ?? .locked).localizedDescription } }
        }
    }
}
