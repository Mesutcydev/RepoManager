import SwiftUI
import UIKit
import RepoManagerCore
import RepoManagerUI

enum AppGitHubConfiguration {
    static var current: GitHubAppConfiguration? {
        #if DEBUG
        if DevelopmentFixtures.githubPairing {
            return try? GitHubAppConfiguration(clientID: "Iv1.0000000000000001", appSlug: "repo-manager-ui-test")
        }
        #endif
        return try? GitHubAppConfiguration(
            clientID: Bundle.main.object(forInfoDictionaryKey: "RepoManagerGitHubClientID") as? String,
            appSlug: Bundle.main.object(forInfoDictionaryKey: "RepoManagerGitHubAppSlug") as? String)
    }
}

struct GitHubPairingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var advanced = false
    @State private var pat = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RMLayout.groupGap) {
                    GitHubConnectionHeading()
                    if let authorization = model.githubSignIn.authorization {
                        GitHubDeviceCodeView(authorization: authorization,
                            openBrowser: { Task { await model.githubSignIn.openSafari(using: model) } },
                            cancel: { model.githubSignIn.cancel() })
                    } else if AppGitHubConfiguration.current != nil {
                        Button { model.githubSignIn.begin(using: model) } label: {
                            HStack(spacing: RMLayout.elementGap) {
                                if model.githubSignIn.busy { ProgressView().tint(RMPalette.onSend) }
                                Text(model.githubSignIn.busy ? "Connecting…" : "Continue with GitHub")
                                Spacer(minLength: RMLayout.elementGap)
                                Image(systemName: "arrow.up.forward.app")
                            }
                        }.rmProminentButton().disabled(model.githubSignIn.busy || model.locked)
                            .accessibilityIdentifier("github.connect")
                    } else {
                        RMInlineNotice(title: "Update to connect GitHub",
                            detail: "GitHub sign-in is unavailable in this build. Update Repo Manager, or use a fine-grained token below.",
                            symbol: "arrow.down.app")
                            .accessibilityIdentifier("github.configurationUnavailable")
                    }
                    if let error = model.githubSignIn.error {
                        RMInlineNotice(title: "Connection needs attention", detail: error, symbol: "exclamationmark.circle", isError: true)
                            .accessibilityIdentifier("github.error")
                    }
                    if AppGitHubConfiguration.current != nil, model.githubSignIn.authorization == nil {
                        GitHubRepositoryAccessView(openBrowser: { Task { await model.githubSignIn.openSafari(using: model, repositoryAccess: true) } })
                            .disabled(model.githubSignIn.busy || model.locked)
                    }
                    Label("Every remote change needs your review.", systemImage: "checkmark.shield")
                        .font(RMType.meta).foregroundStyle(RMPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Button(advanced ? "Hide token connection" : "Use a token instead") { advanced.toggle(); pat = "" }
                        .rmTextButton().disabled(model.githubSignIn.busy)
                        .accessibilityIdentifier("github.advanced")
                    if advanced {
                        GitHubTokenEntryView(token: $pat, busy: model.githubSignIn.busy, locked: model.locked) {
                            let value = pat; pat = ""
                            model.githubSignIn.connectToken(value, using: model)
                        }
                    }
                }.padding(RMLayout.pageInset).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.background(RMPageBackground()).scrollBounceBehavior(.basedOnSize)
                .navigationTitle("GitHub").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.githubSignIn.cancel(); dismiss() }.accessibilityIdentifier("github.cancel")
                } }
                .onChange(of: model.githubSignIn.state.phase) { _, phase in if phase == .connected { dismiss() } }
                // A delayed disappearance from the pre-Safari presentation can
                // arrive after foreground restoration. Only explicit cancel
                // actions end an active attempt; the secure token field clears
                // on every disappearance. The toolbar always offers Cancel.
                .interactiveDismissDisabled(model.githubSignIn.busy || model.githubSignIn.authorization != nil)
                .onDisappear { pat = "" }
        }
    }
}

private struct GitHubConnectionHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.cardInset) {
            RMBrandGlyph().frame(width: RMLayout.heroTile, height: RMLayout.heroTile)
            RMPageHeading("Connect GitHub", detail: "Sign in with Safari. You choose the repositories Repo Manager can access.")
        }
    }
}

private struct GitHubDeviceCodeView: View {
    let authorization: DeviceAuthorization
    let openBrowser: () -> Void
    let cancel: () -> Void
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.cardInset) {
            Label("1. Copy your code", systemImage: "doc.on.doc")
                .font(RMType.detail.weight(.semibold))
            HStack(spacing: RMLayout.rowGap) {
                Text(authorization.userCode).font(.system(.title2, design: .monospaced).weight(.semibold))
                    .tracking(2).privacySensitive().accessibilityIdentifier("github.userCode")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    SafeClipboard.copyResponse(authorization.userCode); copied = true
                } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .rmIconButton().accessibilityLabel(copied ? "Code copied" : "Copy GitHub code")
                    .accessibilityIdentifier("github.copyCode")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment:.leading,spacing:RMLayout.cardInset) {
                    Text(context.date >= authorization.expires ? "This code has expired. Cancel and start again." : "Code expires in \(max(0, Int(authorization.expires.timeIntervalSince(context.date)))) seconds.")
                        .font(RMType.meta).foregroundStyle(RMPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        SafeClipboard.copyResponse(authorization.userCode); copied = true
                        openBrowser()
                    } label: {
                        HStack { Text("2. Open Safari"); Spacer(minLength:RMLayout.elementGap); Image(systemName:"safari") }
                    }.rmProminentButton().disabled(context.date >= authorization.expires)
                        .accessibilityIdentifier("github.authorize")
                }
            }
            Text("Open Safari also copies your code. Paste it on GitHub and approve the connection, then return to Repo Manager to finish.")
                .font(RMType.detail).foregroundStyle(RMPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: RMLayout.elementGap) {
                ProgressView().controlSize(.small)
                Text("Waiting for your GitHub approval…").font(RMType.meta)
            }.foregroundStyle(RMPalette.secondary)
            Button("Cancel sign-in", action: cancel).rmTextButton()
                .accessibilityIdentifier("github.cancelAttempt")
        }.padding(RMLayout.cardInset).rmSurface()
    }
}

private struct GitHubRepositoryAccessView: View {
    let openBrowser: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.elementGap) {
            Text("Repository access").font(RMType.rowTitle)
            Text("Signing in connects your account. Install the GitHub App to choose which repositories it can use.")
                .font(RMType.detail).foregroundStyle(RMPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose repository access on GitHub", systemImage: "folder.badge.plus", action: openBrowser)
                .rmSecondaryButton().accessibilityIdentifier("github.repositoryAccess")
        }
    }
}

private struct GitHubTokenEntryView: View {
    @Binding var token: String
    let busy: Bool
    let locked: Bool
    let connect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.rowGap) {
            Text("Fine-grained token").font(RMType.rowTitle)
            Text("Limit the token to the repositories and permissions you need. Credentials stay in this device’s Keychain.")
                .font(RMType.detail).foregroundStyle(RMPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("GitHub fine-grained token", text: $token)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .rmField()
                .accessibilityIdentifier("github.token")
            Button("Connect token", action: connect).rmSecondaryButton()
                .disabled(busy || !token.hasPrefix("github_pat_") || token.count < 30 || token.count > 255 || locked)
                .accessibilityIdentifier("github.connectToken")
        }
    }
}
