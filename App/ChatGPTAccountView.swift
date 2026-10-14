import SwiftUI
import UIKit
import RepoManagerCore
import RepoManagerUI

struct ChatGPTAccountView: View {
    @Bindable var model: AppModel
    let initial: ProviderProfile
    @Environment(\.dismiss) private var dismiss
    @State private var title = "ChatGPT"
    @State private var consent = false
    @State private var signingOut = false
    var body: some View {
        let profile = model.data.providers.first(where:{ $0.id == initial.id }) ?? initial
        let session = model.chatGPTSessions[initial.id]
        let busy = model.chatGPTSignIn.busy || signingOut
        NavigationStack {
            RMForm {
                Section("Use your ChatGPT plan") {
                    TextField("Account label",text:$title)
                    ChatGPTConnectionDetails(session:session,account:profile.chatGPTAccount)
                    Text("Eligible ChatGPT Plus and Pro users can use their plan for AI requests in Repo Manager. You can review app access and usage in ChatGPT settings.")
                    Text("Sign in with Safari. After approving access, return to Repo Manager to finish connecting.")
                }
                ChatGPTDestinationDisclosure(consent:$consent)
                Section {
                    if AppChatGPTConfiguration.enabled {
                        ChatGPTContinueButton(busy:model.chatGPTSignIn.busy) {
                            var connecting = profile
                            connecting.title = title.trimmingCharacters(in:.whitespacesAndNewlines)
                            connecting.consentEndpoint = consent ? connecting.endpoint : nil
                            model.chatGPTSignIn.begin(profile:connecting,using:model,
                                requestConsent:session?.connected == true && session?.planUsageEnabled != true)
                        }.disabled(busy || !consent || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        if model.chatGPTSignIn.busy,model.chatGPTSignIn.profileID == initial.id {
                            Text(model.chatGPTSignIn.waitingForSafari ? "Waiting for approval in Safari…" : "Finishing connection…")
                                .accessibilityIdentifier("chatgpt.pending")
                            if model.chatGPTSignIn.waitingForSafari {
                                Button("Open Safari") {
                                    Task { do { try await model.chatGPTSignIn.openSafari(using:model) } catch { model.showProviderError(error) } }
                                }.accessibilityIdentifier("chatgpt.openSafari")
                            }
                            Button("Cancel sign-in",role:.cancel) { model.chatGPTSignIn.cancel() }
                                .accessibilityIdentifier("chatgpt.cancelAttempt")
                        }
                    } else { Text("ChatGPT sign-in is unavailable in this build. Choose another provider to continue.") }
                    if let error = model.chatGPTSignIn.error,model.chatGPTSignIn.profileID == initial.id { Text(error).foregroundStyle(RMPalette.red) }
                }
                if session?.connected == true {
                    ChatGPTAccountActions(planUsageEnabled:session?.planUsageEnabled == true,busy:busy) {
                        signingOut = true
                        Task { await model.signOutChatGPT(initial.id); signingOut = false }
                    }
                }
                if !profile.models.isEmpty {
                    Section("Available models") {
                        ForEach(profile.models) { metadata in Text(metadata.displayName ?? metadata.id) }
                    }
                }
            }
            .navigationTitle("ChatGPT account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Done") {
                        if model.chatGPTSignIn.profileID == initial.id { model.chatGPTSignIn.cancel() }
                        dismiss()
                    }.accessibilityIdentifier("chatgpt.done")
                }
                if model.data.providers.contains(where:{ $0.id == initial.id }) {
                    ToolbarItem(placement:.confirmationAction) {
                        Button("Save") {
                            Task {
                                do {
                                    var edited = profile; edited.title = title.trimmingCharacters(in:.whitespacesAndNewlines)
                                    edited.consentEndpoint = consent ? edited.endpoint : nil
                                    try await model.upsertProvider(edited,credential:""); dismiss()
                                } catch { model.showProviderError(error) }
                            }
                        }.disabled(busy || title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { title = initial.title; consent = initial.consentEndpoint == initial.endpoint }
            .task {
                guard let runtime = model.runtime else { return }
                do { model.chatGPTSessions[initial.id] = try await runtime.chatGPT.session(initial.id) }
                catch { model.showProviderError(error) }
            }
            .interactiveDismissDisabled(busy)
            // Background locking removes the sheet. Only explicit user cancel
            // ends a pending Safari attempt, including delayed disappearances.
            .alert("You're using your ChatGPT plan",isPresented:$model.chatGPTPlanWelcomePresented) {
                Button("Got it",role:.cancel) {}
            } message: {
                Text("Eligible AI requests in Repo Manager use your ChatGPT plan. Manage this app's access and usage in ChatGPT settings.")
            }
        }
    }
}

private struct ChatGPTConnectionDetails: View {
    let session: ChatGPTSession?
    let account: ChatGPTAccount?
    var body: some View {
        if let account {
            Text(account.label).privacySensitive()
            Text("Connection \(account.registrationLabel)").font(RMType.meta).foregroundStyle(RMPalette.secondary)
        }
        if session?.planUsageEnabled == true { Label("Using ChatGPT plan",systemImage:"checkmark.circle.fill").foregroundStyle(RMPalette.accentText) }
        else if session?.connected == true { Text("Connected · ChatGPT plan usage is disabled") }
        else { Text("Sign in to connect this account").foregroundStyle(RMPalette.secondary) }
    }
}

private struct ChatGPTDestinationDisclosure: View {
    @Binding var consent: Bool
    var body: some View {
        Section("Your content") {
            Text("Conversation text, attached documents, and selected repository context are sent to OpenAI at api.openai.com. OpenAI's retention policies apply. This connection does not give Repo Manager access to your ChatGPT conversations.")
            Toggle("Allow requests to OpenAI",isOn:$consent).accessibilityIdentifier("chatgpt.disclosure")
        }
    }
}

private struct ChatGPTAccountActions: View {
    let planUsageEnabled: Bool
    let busy: Bool
    let signOut: () -> Void
    var body: some View {
        Section("Account and usage") {
            Link("Manage usage",destination:ChatGPTAuth.usageURL).accessibilityIdentifier("chatgpt.manageUsage")
            if !planUsageEnabled { Text("Continue with ChatGPT above to enable plan usage, or choose an API-key provider.") }
            Button("Sign out of this account",role:.destructive,action:signOut).disabled(busy)
        }
    }
}

struct ChatGPTContinueButton: View {
    let busy: Bool
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:12) {
                if busy { ProgressView().tint(.white) }
                Text("Continue with ChatGPT").font(.body.weight(.semibold))
            }
            .foregroundStyle(.white).frame(maxWidth:.infinity,minHeight:48)
            .background(.black,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.2),lineWidth:1))
            .contentShape(RoundedRectangle(cornerRadius:12))
        }.buttonStyle(RMPressButtonStyle()).accessibilityIdentifier("chatgpt.continue")
    }
}

struct ChatGPTUsageStrip: View {
    var body: some View {
        HStack {
            Text("Using ChatGPT plan")
            Spacer(minLength:8)
            Link("Manage usage",destination:ChatGPTAuth.usageURL)
        }.font(RMType.meta).foregroundStyle(RMPalette.secondary)
            .padding(.horizontal,RMLayout.pageInset).padding(.top,8)
            .accessibilityIdentifier("chatgpt.planUsage")
    }
}

