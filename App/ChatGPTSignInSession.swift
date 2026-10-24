import Foundation
import Observation
import UIKit
import RepoManagerCore

enum AppChatGPTConfiguration {
    static var enabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey:"RepoManagerChatGPTPlanUsageEnabled") as? String)?.uppercased() == "YES"
    }
}

/// Owns the short-lived OAuth continuation independently of the account sheet.
/// Safari/passkey handoff locks the workspace, but retains state, nonce, PKCE
/// and the loopback listener until foreground restoration or explicit cancel.
@MainActor @Observable final class ChatGPTSignInSession {
    private(set) var busy = false
    private(set) var profileID: UUID?
    private(set) var error: String?
    private(set) var waitingForSafari = false
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored private var task: Task<Void,Never>?
    @ObservationIgnored private var listener: ChatGPTLoopbackListener?
    @ObservationIgnored private var attempt: ChatGPTAuthorizationAttempt?
    @ObservationIgnored private var foreground: CheckedContinuation<Void,Never>?
    @ObservationIgnored private var completing = false
    @ObservationIgnored private var backgrounded = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var browserReturnURL: URL?

    var pendingAttemptID: UUID? { completing ? nil : attempt?.id }
    func acceptsBrowserReturn(_ url: URL) -> Bool { browserReturnURL == url }

    func begin(profile: ProviderProfile, using model: AppModel, requestConsent: Bool = false) {
        guard !busy,!model.locked,AppChatGPTConfiguration.enabled,let runtime = model.runtime else { return }
        cancel(); error = nil
        let ticket = UUID()
        operationID = ticket; profileID = profile.id; busy = true; backgrounded = false
        task = Task { [weak self,weak model] in
            guard let self,let model else { return }
            let listener = ChatGPTLoopbackListener(); self.listener = listener
            var pending: ChatGPTAuthorizationAttempt?
            do {
                try ChatGPTAuth.validateProfile(profile)
                guard profile.consentEndpoint == profile.endpoint else { throw RMError.consentRequired }
                if !model.data.providers.contains(where:{ $0.id == profile.id }) { try await model.upsertProvider(profile,credential:"") }
                let callbackURI = try await listener.start()
                let authorization = try await runtime.chatGPT.begin(profileID:profile.id,redirectURI:callbackURI,requestConsent:requestConsent)
                pending = authorization
                try Task.checkCancellation(); guard valid(ticket,model:model,runtime:runtime),!backgrounded else { throw RMError.cancelled }
                attempt = authorization
                let returnURL = URL(string:"com.mesutcydev.repomanager.chatgpt://complete/"+UUID().uuidString)!
                browserReturnURL = returnURL
                try await listener.expect(authorization,browserReturnURL:returnURL)
                waitingForSafari = true
                try await openSafari(using:model)
                let callback = try await listener.waitForCallback()
                waitingForSafari = false; endBackgroundTask()
                // Safari can deliver a callback while it is foreground. Wait
                // until the encrypted workspace has been restored to exchange.
                try await waitForForeground(ticket,model:model,runtime:runtime)
                completing = true
                let lease = model.lifecycleID
                let session = try await runtime.chatGPT.complete(authorization,callbackURL:callback)
                try Task.checkCancellation()
                guard valid(ticket,model:model,runtime:runtime),!model.locked,model.lifecycleID == lease else { throw RMError.cancelled }
                try await model.applyChatGPTConnection(session,profileID:profile.id)
            } catch {
                if operationID == ticket,error as? RMError != .cancelled,!(error is CancellationError) {
                    self.error = ProviderFailure.safe(error).localizedDescription
                    if let failure = error as? ChatGPTServiceError,failure.requiresUsageManagement { model.showProviderError(error) }
                }
            }
            if let pending { await runtime.chatGPT.cancel(pending) }
            await listener.stop()
            if operationID == ticket {
                operationID = nil; busy = false; self.listener = nil; attempt = nil
                task = nil; completing = false; waitingForSafari = false; endBackgroundTask()
                browserReturnURL = nil
            }
        }
    }

    func openSafari(using model: AppModel) async throws {
        guard !model.locked,!model.loading,let attempt,let ticket = operationID,waitingForSafari,
              Date() < attempt.expiresAt,UIApplication.shared.applicationState == .active else { throw RMError.cancelled }
        // A finite OS grace period lets a prompt return through loopback while
        // Safari is foreground. Expiration ends only that grace period; the
        // pending attempt can resume when the user returns to the app.
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName:"ChatGPT sign-in callback") { [weak self] in
                Task { @MainActor in self?.endBackgroundTask() }
            }
        }
        var destination = attempt.authorizationURL
        #if DEBUG
        if DevelopmentFixtures.chatGPTPairing {
            // Exercise the real local listener and external Safari without
            // authorizing an OpenAI account. Invalid state leaves it pending.
            var fixture = URLComponents(url:attempt.redirectURI,resolvingAgainstBaseURL:false)!
            fixture.queryItems = [.init(name:"code",value:"synthetic-code"),.init(name:"state",value:"invalid-fixture-state")]
            destination = fixture.url!
        }
        #endif
        let opened = await UIApplication.shared.open(destination)
        guard operationID == ticket else { throw RMError.cancelled }
        if !opened { endBackgroundTask(); throw ChatGPTSignInError.browserUnavailable }
    }

    func suspendForBackground() async {
        backgrounded = true
        // An exchange already consumes its one-use code. Abort late writes;
        // reconnect with the saved registration rather than retrying the code.
        if busy,(attempt == nil || completing) {
            let pending = task
            cancel(clearError:false)
            error = String(localized:"Sign-in was interrupted. Continue with ChatGPT to reconnect.")
            await pending?.value
        }
    }

    func resume(using model: AppModel) {
        guard !model.locked,!model.loading else { return }
        backgrounded = false
        if let attempt,Date() >= attempt.expiresAt {
            cancel(clearError:false); error = ChatGPTSignInError.expired.localizedDescription
        }
        foreground?.resume(); foreground = nil
    }

    func cancel(clearError: Bool = true) {
        operationID = nil; task?.cancel(); task = nil
        foreground?.resume(); foreground = nil
        if let listener { Task { await listener.stop() } }; listener = nil
        attempt = nil; busy = false; completing = false; waitingForSafari = false; endBackgroundTask()
        browserReturnURL = nil
        if clearError { error = nil }
    }

    private func waitForForeground(_ ticket: UUID,model: AppModel,runtime: AppRuntime) async throws {
        while true {
            try Task.checkCancellation()
            guard valid(ticket,model:model,runtime:runtime) else { throw RMError.cancelled }
            if !backgrounded,!model.locked,!model.loading,UIApplication.shared.applicationState == .active { return }
            await withCheckedContinuation { foreground = $0 }
        }
    }
    private func valid(_ ticket: UUID,model: AppModel,runtime: AppRuntime) -> Bool {
        operationID == ticket && model.runtime === runtime
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
    }
}
