import SwiftUI
import RepoManagerCore
import RepoManagerUI

@main struct RepoManagerApp: App {
    @State private var model = AppModel()
    init() { BackgroundNetworking.shared.register() }
    var body: some Scene {
        WindowGroup { RootView(model:model).rmAdaptiveBarsEnvironment() }
        .commands {
            CommandGroup(replacing:.newItem) { Button("New chat") { model.newChat() }.keyboardShortcut("n") }
            CommandMenu("Repo Manager") {
                Button("Changes") { model.selection = .changes }.keyboardShortcut("d",modifiers:[.command,.shift])
                Button("Stop") { model.stop(); model.stopVoice() }.keyboardShortcut(".")
                Button("Repositories") { model.selection = .repositories }.keyboardShortcut("r",modifiers:[.command,.shift])
            }
        }
    }
}
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var nativeTypeSize
    @Environment(\.layoutDirection) private var nativeDirection
    @State private var settings = false
    @State private var recovery = false
    @State private var splashFinished = false
    @State private var lifecycleTransition: Task<Void, Never>?
    var body: some View {
        ZStack {
            if !splashFinished {
                RMSplashScreen(ready:!model.loading,reduceMotion:DevelopmentFixtures.reducedMotion) {
                    withAnimation(.easeOut(duration:0.18)) { splashFinished = true }
                }.transition(.opacity)
            }
            else if model.loading { ProgressView("Opening encrypted workspace…") }
            else if model.locked {
                ContentUnavailableView {
                    Label("Encrypted workspace locked",systemImage:"lock.shield")
                } description: { Text(model.error ?? String(localized:"Unlock your device to continue.")) }
                  actions: {
                      Button("Try unlocking") { Task { await model.load() } }
                      Button("Recovery options") { recovery = true }
                  }
            } else if model.data.preferences.onboardingCompleted != true {
                OnboardingView(model:model).transition(.opacity)
            } else {
                // ponytail: recents re-sort on each render; cache in AppModel if history grows into the thousands.
                RMWorkbench(selection:$model.selection,
                            recents:model.data.conversations.filter { !$0.archived }.sorted {
                                if $0.pinned != $1.pinned { return $0.pinned }
                                return $0.modified > $1.modified
                            }.prefix(8)
                                .map { RMRecentChat(id:$0.id.uuidString,title:$0.title,detail:$0.repository?.name ?? $0.modified.formatted(.relative(presentation:.named))) },
                            currentRecentID:model.selectedConversationID?.uuidString,
                            openRecent:{ if let id = UUID(uuidString:$0) { model.selectChat(id) } },
                            settings:{ settings = true },newChat:model.newChat,
                            principal:{ $0 == .chat && model.conversation != nil ? AnyView(ChatModelButton(model:model)) : nil },
                            actions:{ $0 == .chat && model.conversation != nil ? AnyView(ChatActionsMenu(model:model)) : nil }) { destination in
                    switch destination {
                    case .chats: AnyView(HistoryView(model:model))
                    case .chat: AnyView(ChatView(model:model))
                    case .providers: AnyView(ProvidersView(model:model))
                    case .repositories: AnyView(RepositoriesView(model:model))
                    case .changes: AnyView(ChangesView(model:model))
                    case .tools: AnyView(ToolsView(model:model))
                    case .voice: AnyView(VoiceView(model:model))
                    case .apiServer: AnyView(APIServerView(model:model))
                    default: AnyView(ManagementView(model:model,destination:destination))
                    }
                }.transition(.opacity)
            }
        }
        .background(RMBrand.canvas.ignoresSafeArea())
        .environment(\.dynamicTypeSize,DevelopmentFixtures.largeText ? .accessibility3 : nativeTypeSize)
        .environment(\.layoutDirection,DevelopmentFixtures.rtl ? .rightToLeft : nativeDirection)
        .environment(\.rmReduceMotionOverride,DevelopmentFixtures.reducedMotion)
        .environment(\.rmAppearance,model.appearance).preferredColorScheme(model.appearance.colorScheme).tint(RMPalette.accentText)
        .sheet(isPresented:$settings) { SettingsView(model:model) }
        .sheet(isPresented:$recovery) { VaultRecoveryView(model:model) }
        .sheet(isPresented:$model.githubPairingResumePresented) { GitHubPairingView(model:model) }
        .sheet(item:$model.chatGPTSignInResumeProfile) { ChatGPTAccountView(model:model,initial:$0) }
        .onOpenURL { url in
            guard model.chatGPTSignIn.acceptsBrowserReturn(url) else { return }
            Task { await model.becameActive() }
        }
        // A root SwiftUI alert cannot present over sheets; it dismissed the open sheet and lost the message.
        .onChange(of:model.error) { _, message in if let message, !model.locked { ErrorPresenter.show(message,manageUsage:model.chatGPTUsageLimitReached) { model.error = nil; model.chatGPTUsageLimitReached = false } } }
        .task { await model.load() }
        .onChange(of:phase) { _, value in
            let previous = lifecycleTransition
            lifecycleTransition = Task {
                await previous?.value
                if value != .active {
                    if value == .background { BackgroundNetworking.shared.schedule(enabled:model.data.preferences.backgroundNetworkRefresh == true,sync:model.data.preferences.syncHistory) }
                    await model.inactive(background:value == .background)
                } else { BackgroundNetworking.shared.cancelRunning(); await model.becameActive() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in BackgroundNetworking.shared.cancelRunning(); Task { await model.inactive(background:true); await model.stopServer() } }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.willTerminateNotification)) { _ in Task { await model.stopServer() } }
        .task {
            if !DevelopmentFixtures.enabled, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:SharedInbox.group) {
                do { try SharedInbox.prepare(root:container.appendingPathComponent("EncryptedInbox")) } catch { /* No plaintext fallback. Import explains unavailability. */ }
            }
        }
    }
}
/// Presents errors from the topmost view controller so they appear above open sheets without dismissing them.
@MainActor enum ErrorPresenter {
    private static weak var current: UIAlertController?
    static func show(_ message:String,manageUsage:Bool = false,dismissed:@escaping () -> Void) {
        if let current,current.presentingViewController != nil {
            current.message = message
            if manageUsage { addUsageAction(to:current,dismissed:dismissed) }; return
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard var top = (windows.first(where:\.isKeyWindow) ?? windows.first { $0.windowLevel == .normal })?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let alert = UIAlertController(title:"Repo Manager",message:message,preferredStyle:.alert)
        if manageUsage { addUsageAction(to:alert,dismissed:dismissed) }
        alert.addAction(UIAlertAction(title:String(localized:"OK"),style:.default) { _ in dismissed() })
        top.present(alert,animated:true); current = alert
    }
    private static func addUsageAction(to alert:UIAlertController,dismissed:@escaping () -> Void) {
        guard !alert.actions.contains(where:{ $0.title == String(localized:"Manage usage") }) else { return }
        let action = UIAlertAction(title:String(localized:"Manage usage"),style:.default) { _ in
            UIApplication.shared.open(ChatGPTAuth.usageURL); dismissed()
        }
        alert.addAction(action); alert.preferredAction = action
    }
}
