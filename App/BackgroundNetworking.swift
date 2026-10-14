import BackgroundTasks
import Foundation
import UIKit
import RepoManagerCore

/// Background refresh has no provider inference, tool execution, approvals, voice, or listener.
@MainActor final class BackgroundNetworking {
    static let shared = BackgroundNetworking()
    static let refreshID = "com.mesutcydev.repomanager.refresh"
    static let processingID = "com.mesutcydev.repomanager.history-sync"
    private var registered = false
    private var workers: [UUID:Task<Void,Never>] = [:]
    private init() {}
    func register() {
        #if !targetEnvironment(macCatalyst)
        guard !registered else { return }; registered = true
        for id in [Self.refreshID,Self.processingID] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier:id,using:.main) { task in
                let box = BackgroundTaskBox(task)
                Task { @MainActor in self.handle(box) }
            }
        }
        #endif
    }
    func schedule(enabled:Bool,sync:Bool) {
        #if !targetEnvironment(macCatalyst)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.refreshID)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:Self.processingID)
        guard enabled,!DevelopmentFixtures.enabled else { return }
        let refresh = BGAppRefreshTaskRequest(identifier:Self.refreshID)
        refresh.earliestBeginDate = Date().addingTimeInterval(15*60)
        try? BGTaskScheduler.shared.submit(refresh)
        if sync {
            let processing = BGProcessingTaskRequest(identifier:Self.processingID)
            processing.requiresNetworkConnectivity = true; processing.requiresExternalPower = false
            processing.earliestBeginDate = Date().addingTimeInterval(30*60)
            try? BGTaskScheduler.shared.submit(processing)
        }
        #endif
    }
    func cancelRunning() { for task in workers.values { task.cancel() }; workers.removeAll() }
    private func handle(_ box:BackgroundTaskBox) {
        let id = UUID()
        let task = Task {
            var success = false
            do {
                guard UIApplication.shared.applicationState != .active,UIApplication.shared.isProtectedDataAvailable,!DevelopmentFixtures.enabled else { throw RMError.locked }
                let support = try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:false)
                let vault = try SecureStore(root:support.appendingPathComponent("RepoManager/Vault"))
                guard let data = try await vault.load(AppData.self,id:"app-data"),data.preferences.backgroundNetworkRefresh == true else { throw RMError.forbidden }
                let connections = GitHubConnectionStore(vault:vault); _ = try await connections.restore()
                let github = GitHubClient(connections:connections,vault:vault)
                let scopes = BackgroundRefreshPolicy.scopes(data)
                for scope in scopes {
                    try Task.checkCancellation(); guard UIApplication.shared.isProtectedDataAvailable else { throw RMError.locked }
                    // Refresh identity and head only. No contents, writes, billed inference, or background credential refresh after lock.
                    _ = try await github.verify(scope); _ = try await github.head(scope,allowOffline:true)
                }
                if data.preferences.syncHistory,box.task.identifier == Self.processingID {
                    guard AppleCapability.cloudKitProvisioned else { throw RMError.unavailable }
                    let merged = try await HistorySync().synchronize(data)
                    try Task.checkCancellation(); guard UIApplication.shared.applicationState != .active,UIApplication.shared.isProtectedDataAvailable else { throw RMError.cancelled }
                    let history = merged.conversations.map(HistoryRecord.init)+merged.tombstones.map { HistoryRecord(tombstone:$0.key,date:$0.value) }
                    try await vault.save(history,id:"pending-history-import")
                }
                success = true
                schedule(enabled:true,sync:data.preferences.syncHistory)
            } catch { /* Safe failure: no plaintext diagnostics, automatic inference, or write retry. */ }
            box.task.setTaskCompleted(success:success); workers[id] = nil
        }
        workers[id] = task
        box.task.expirationHandler = { task.cancel() }
    }
}
private final class BackgroundTaskBox: @unchecked Sendable {
    let task:BGTask
    init(_ task:BGTask) { self.task = task }
}
