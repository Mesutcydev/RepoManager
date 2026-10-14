import Foundation
import Observation
import UIKit
import RepoManagerCore

/// The app owns this short-lived continuation so locking the workspace does not
/// destroy a Safari sign-in. Polling stops before browser handoff and resumes only
/// after the encrypted workspace is restored in the foreground.
@MainActor @Observable final class GitHubSignInSession {
    private(set) var state = GitHubDeviceFlowState()
    private(set) var error: String?
    private(set) var browserReturnPending = false
    @ObservationIgnored private var task: Task<Void, Never>?

    var authorization: DeviceAuthorization? { state.authorization }
    var busy: Bool { state.phase == .requesting || state.phase == .waiting }

    func begin(using model: AppModel) {
        guard !busy, !model.locked, let runtime = model.runtime,
              let configuration = AppGitHubConfiguration.current else { return }
        cancel(); error = nil
        let ticket = state.begin(), lease = model.lifecycleID
        task = Task { [weak self, weak model] in
            guard let self else { return }
            do {
                let flow = try await runtime.connections.beginDeviceFlow(clientID: configuration.clientID)
                try Task.checkCancellation()
                guard let model, self.valid(ticket, model: model, lease: lease),
                      self.state.receive(flow, ticket: ticket) else { return }
                try await self.poll(flow, ticket: ticket, runtime: runtime, model: model, lease: lease)
            } catch { self.finish(error, ticket: ticket) }
        }
    }

    func connectToken(_ credential: String, using model: AppModel) {
        guard !busy, !model.locked, let runtime = model.runtime else { return }
        cancel(); error = nil
        let ticket = state.begin(), lease = model.lifecycleID
        task = Task { [weak self, weak model] in
            guard let self else { return }
            do {
                _ = try await runtime.connections.connectPAT(credential)
                try Task.checkCancellation()
                guard let model, self.valid(ticket, model: model, lease: lease) else { return }
                try await self.connected(ticket: ticket, runtime: runtime, model: model, lease: lease)
            } catch { self.finish(error, ticket: ticket) }
        }
    }

    func suspendForBackground() async {
        let pending = task
        state.suspend(); task = nil
        pending?.cancel()
        await pending?.value
    }

    func openSafari(using model: AppModel, repositoryAccess: Bool = false) async {
        guard !model.locked, let configuration = AppGitHubConfiguration.current else { return }
        let destination: URL
        if repositoryAccess { destination = configuration.installationURL }
        else if let authorization { destination = authorization.verificationURL }
        else { return }
        browserReturnPending = true
        await suspendForBackground()
        guard UIApplication.shared.applicationState == .active, !model.locked else { return }
        // Match SiteAgent's external HTTPS handoff; this uses the system browser
        // (Safari by default), never SFSafariViewController or an embedded web view.
        let opened = await UIApplication.shared.open(destination)
        if !opened {
            browserReturnPending = false
            error = GitHubPairingError.browserUnavailable.localizedDescription
            resume(using: model)
        }
    }

    func resume(using model: AppModel) {
        guard !model.locked, let runtime = model.runtime,
              AppGitHubConfiguration.current != nil else { return }
        browserReturnPending = false
        do {
            guard let (ticket, flow) = try state.resume() else { return }
            let lease = model.lifecycleID
            task = Task { [weak self, weak model] in
                guard let self, let model else { return }
                do { try await self.poll(flow, ticket: ticket, runtime: runtime, model: model, lease: lease) }
                catch { self.finish(error, ticket: ticket) }
            }
        } catch { self.error = GitHubPairingError.expired.localizedDescription }
    }

    func cancel() {
        state.cancel(); task?.cancel(); task = nil
        browserReturnPending = false; error = nil
    }

    private func poll(_ flow: DeviceAuthorization, ticket: UUID, runtime: AppRuntime,
                      model: AppModel, lease: UInt64) async throws {
        guard let configuration = AppGitHubConfiguration.current else { throw GitHubPairingError.configurationUnavailable }
        _ = try await runtime.connections.completeDeviceFlow(flow, clientID: configuration.clientID) { [weak self] interval in
            await MainActor.run { self?.state.updateInterval(interval, ticket: ticket) }
        }
        try Task.checkCancellation()
        guard valid(ticket, model: model, lease: lease) else { return }
        try await connected(ticket: ticket, runtime: runtime, model: model, lease: lease)
    }

    private func connected(ticket: UUID, runtime: AppRuntime, model: AppModel, lease: UInt64) async throws {
        let accounts = await runtime.connections.savedAccounts()
        try Task.checkCancellation()
        guard valid(ticket, model: model, lease: lease), state.complete(ticket: ticket) else { return }
        model.data.accounts = accounts
        await model.flush()
        guard valid(ticket, model: model, lease: lease) else { return }
        task = nil; error = nil
    }

    private func valid(_ ticket: UUID, model: AppModel, lease: UInt64) -> Bool {
        state.ticket == ticket && !model.locked && model.lifecycleID == lease
    }

    private func finish(_ failure: Error, ticket: UUID) {
        guard state.ticket == ticket else { return }
        task = nil
        if failure is CancellationError || (failure as? RMError) == .cancelled { return }
        state.cancel()
        error = (failure as? GitHubPairingError)?.localizedDescription
            ?? (failure as? RMError ?? .authentication).localizedDescription
    }
}
