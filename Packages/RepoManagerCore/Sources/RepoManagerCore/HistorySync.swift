import Foundation
import CloudKit

public struct HistoryRecord: Codable, Sendable {
    public var conversation: Conversation?; public var id: UUID; public var modified: Date; public var deleted: Bool
    public init(conversation: Conversation) {
        var c = conversation; c.draft = ""; c.attachments = []; c.readingMessageID = nil; c.fileEditorDrafts = nil
        c.providerID = nil; c.repository = nil
        self.conversation = c; id = c.id; modified = c.modified; deleted = false
    }
    public init(tombstone: UUID, date: Date) { conversation = nil; id = tombstone; modified = date; deleted = true }
}
public enum HistoryMerge {
    public static func merge(local: AppData, remote: [HistoryRecord]) -> AppData {
        var data = local
        for record in remote {
            if record.deleted {
                if let existing = data.conversations.first(where:{ $0.id == record.id }), existing.modified > record.modified { continue }
                data.conversations.removeAll { $0.id == record.id }; data.tombstones[record.id] = record.modified; continue
            }
            guard var incoming = record.conversation else { continue }
            if let deleted = data.tombstones[record.id], deleted >= incoming.modified { continue }
            if let i = data.conversations.firstIndex(where:{ $0.id == incoming.id }) {
                let current = data.conversations[i]
                let ids = Set(current.messages.map(\.id)); let incomingIDs = Set(incoming.messages.map(\.id))
                if current.messages == incoming.messages, incoming.modified <= current.modified { continue }
                if ids.isSubset(of:incomingIDs), current.messages.allSatisfy({ m in incoming.messages.contains(m) }) {
                    incoming.draft = current.draft; incoming.attachments = current.attachments; incoming.fileEditorDrafts = current.fileEditorDrafts
                    incoming.providerID = current.providerID; incoming.repository = current.repository
                    data.conversations[i] = incoming
                } else if !incomingIDs.isSubset(of:ids) || incoming.messages.contains(where:{ m in current.messages.contains(where:{ $0.id == m.id && $0 != m }) }) {
                    incoming.id = conflictID(record); incoming.title += " (sync conflict)"; incoming.providerID = nil; incoming.repository = nil
                    incoming.draft = ""; incoming.attachments = []; incoming.fileEditorDrafts = nil
                    if !data.conversations.contains(where:{ $0.id == incoming.id }) { data.conversations.append(incoming) }
                }
            } else {
                incoming.providerID = nil; incoming.repository = nil; incoming.draft = ""; incoming.attachments = []
                data.conversations.append(incoming)
            }
        }
        return data
    }
    /// A repeated encrypted import creates the same conflict copy, including after a crash between save and inbox deletion.
    private static func conflictID(_ record:HistoryRecord) -> UUID {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = RecordCrypto.digest((try? encoder.encode(record)) ?? Data(record.id.uuidString.utf8))
        let h = Array(digest.prefix(32)); let raw = String(h[0..<8])+"-"+String(h[8..<12])+"-"+String(h[12..<16])+"-"+String(h[16..<20])+"-"+String(h[20..<32])
        return UUID(uuidString:raw) ?? record.id
    }
}
public actor HistorySync {
    private let containerID: String; private var database: CKDatabase { CKContainer(identifier:containerID).privateCloudDatabase }; private let secrets: any SecretStore
    private let keyName = "history-sync-v1"
    public init(containerID: String = "iCloud.com.mesutcydev.repomanager", secrets: any SecretStore = KeychainStore()) {
        self.containerID = containerID; self.secrets = secrets
    }
    public func synchronize(_ local: AppData) async throws -> AppData {
        guard local.preferences.syncHistory else { throw RMError.forbidden }
        let remote = try await records()
        let key: Data
        if let found = try secrets.read(keyName,synchronizable:true) { guard found.count == 32 else { throw RMError.missingKey }; key = found }
        else {
            guard remote.isEmpty else { throw RMError.missingKey }
            key = try RecordCrypto.random(32); try secrets.write(key,account:keyName,synchronizable:true)
        }
        var clear: [HistoryRecord] = []
        for r in remote {
            guard let ciphertext = r["ciphertext"] as? Data else { throw RMError.corruptRecord }
            clear.append(try JSONDecoder().decode(HistoryRecord.self,from:RecordCrypto.open(ciphertext,key:key,id:r.recordID.recordName)))
        }
        let data = HistoryMerge.merge(local:local,remote:clear)
        let outgoing = data.conversations.map(HistoryRecord.init) + data.tombstones.map { HistoryRecord(tombstone:$0.key,date:$0.value) }
        let existing = Dictionary(remote.map { ($0.recordID.recordName,$0) },uniquingKeysWith:{ a,_ in a })
        for record in outgoing {
            try Task.checkCancellation()
            let name = RecordCrypto.digest(Data(record.id.uuidString.utf8))
            let r = existing[name] ?? CKRecord(recordType:"RMHistory",recordID:CKRecord.ID(recordName:name))
            r["ciphertext"] = try RecordCrypto.seal(JSONEncoder().encode(record),key:key,id:name) as CKRecordValue
            r["version"] = 1 as CKRecordValue
            // CKRecord change tags prevent silently overwriting a concurrent device edit.
            _ = try await database.save(r)
        }
        return data
    }
    private func records() async throws -> [CKRecord] {
        let query = CKQuery(recordType:"RMHistory",predicate:NSPredicate(value:true))
        var result = try await database.records(matching:query,resultsLimit:100)
        var records: [CKRecord] = []
        while true {
            for (_,row) in result.matchResults { records.append(try row.get()) }
            guard records.count <= 2000 else { throw RMError.tooLarge }
            guard let cursor = result.queryCursor else { return records }
            result = try await database.records(continuingMatchFrom:cursor,resultsLimit:100)
        }
    }
}

public enum VoicePhase: String, Sendable { case idle, listening, transcribing, responding, speaking, paused, approval }
public enum VoiceEvent: Sendable { case phase(VoicePhase), transcript(String, final: Bool), failure(RMError) }
@MainActor public protocol VoiceService: AnyObject {
    var events: AsyncStream<VoiceEvent> { get }
    func dictate(locale: String) async throws
    func speak(_ text: String, voiceID: String?, rate: Float)
    func stop()
}
