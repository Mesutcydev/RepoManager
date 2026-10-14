import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct VaultRecoveryView:View {
    @Bindable var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    @State private var busy = false
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    Text("A locked or missing Keychain key never replaces your encrypted records.").font(RMType.rowTitle)
                    Text("First unlock your device and try again. If the device vault key was permanently removed, these records cannot be decrypted. Only an encrypted backup and its passphrase can recover that work.")
                    Divider()
                    Text("Starting a new vault permanently removes Repo Manager’s local records, saved connections, and client grants. It also removes this app’s keys. Other apps and your exported encrypted backups are untouched.").foregroundStyle(RMPalette.secondary)
                    Text("After creating a new vault, import your encrypted backup in Settings. Reconnect providers and GitHub, then review drafts again before publishing.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
                    Text("Local erasure preserves the optional shared history key and does not delete your encrypted iCloud history.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
                    Button("Erase local vault and start again",role:.destructive) { confirm = true }.rmSecondaryButton().disabled(busy || model.runtime == nil)
                    if busy { ProgressView("Authenticating…") }
                }.padding(RMLayout.pageInset).frame(maxWidth:650,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).navigationTitle("Recovery")
            .toolbar { Button("Done") { dismiss() }.disabled(busy) }
            .confirmationDialog("Permanently erase this app’s local encrypted workspace?",isPresented:$confirm,titleVisibility:.visible) {
                Button("Authenticate and erase Repo Manager",role:.destructive) {
                    busy = true
                    Task { defer { busy = false }; do { try await model.wipe(); dismiss() } catch { model.error = (error as? RMError ?? .locked).localizedDescription } }
                }
            }
        }
    }
}
