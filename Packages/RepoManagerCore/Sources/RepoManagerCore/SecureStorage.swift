import Foundation
import Security
import CryptoKit
import Sodium

public protocol SecretStore: Sendable {
    func read(_ account: String, synchronizable: Bool) throws -> Data?
    func write(_ value: Data, account: String, synchronizable: Bool) throws
    func delete(_ account: String, synchronizable: Bool) throws
}
public extension SecretStore {
    func read(_ account: String) throws -> Data? { try read(account, synchronizable: false) }
    func write(_ value: Data, account: String) throws { try write(value, account: account, synchronizable: false) }
    func delete(_ account: String) throws { try delete(account, synchronizable: false) }
}
public struct KeychainStore: SecretStore {
    public static let service = "com.mesutcydev.repomanager.v1"
    private let namespace: String; private let accessGroup: String?
    /// `accessGroup` nil keeps items in the app's own default group; an app-group id shares them with the extension.
    public init(service: String = Self.service, accessGroup: String? = nil) { namespace = service; self.accessGroup = accessGroup }
    private func query(_ account: String, _ sync: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: namespace,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: sync,kSecUseDataProtectionKeychain as String:true]
        if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }
    public func read(_ account: String, synchronizable: Bool = false) throws -> Data? {
        var q = query(account, synchronizable); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw RMError.locked }
        return data
    }
    public func write(_ value: Data, account: String, synchronizable: Bool = false) throws {
        let q = query(account, synchronizable)
        let attrs: [String: Any] = [kSecValueData as String: value,
            kSecAttrAccessible as String: synchronizable ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if update == errSecItemNotFound {
            let add = SecItemAdd(q.merging(attrs) { _, n in n } as CFDictionary, nil)
            guard add == errSecSuccess else { throw RMError.locked }
        } else if update != errSecSuccess { throw RMError.locked }
    }
    public func delete(_ account: String, synchronizable: Bool = false) throws {
        let result = SecItemDelete(query(account, synchronizable) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw RMError.locked }
    }
    /// Local recovery keeps the shared history key, avoiding orphaned encrypted
    /// history on other devices. Only explicit shared-key removal may include it.
    public func wipeOwnedItems(includingSynchronizable:Bool = false) throws {
        let synchronization:Any = includingSynchronizable ? kSecAttrSynchronizableAny : false
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: namespace, kSecAttrSynchronizable as String: synchronization,kSecUseDataProtectionKeychain as String:true] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw RMError.locked }
    }
}

public struct EncryptedEnvelope: Codable, Sendable {
    public var version = 1
    public var combined: Data
    public init(combined: Data) { self.combined = combined }
}
public enum RecordCrypto {
    public static func random(_ count: Int) throws -> Data {
        guard count > 0, count <= 4096 else { throw RMError.invalidInput }
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw RMError.unavailable }
        return Data(bytes)
    }
    public static func seal(_ data: Data, key: Data, id: String) throws -> Data {
        guard key.count == 32 else { throw RMError.missingKey }
        let aad = Data("RepoManager:1:\(id)".utf8)
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: key), authenticating: aad)
        guard let combined = box.combined else { throw RMError.corruptRecord }
        return try JSONEncoder().encode(EncryptedEnvelope(combined: combined))
    }
    public static func open(_ data: Data, key: Data, id: String) throws -> Data {
        guard key.count == 32 else { throw RMError.missingKey }
        do {
            let e = try JSONDecoder().decode(EncryptedEnvelope.self, from: data)
            guard e.version == 1 else { throw RMError.corruptRecord }
            return try AES.GCM.open(AES.GCM.SealedBox(combined: e.combined), using: SymmetricKey(data: key), authenticating: Data("RepoManager:1:\(id)".utf8))
        } catch { throw RMError.corruptRecord }
    }
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// Only ciphertext is written. A missing key never triggers replacement of an existing vault.
public actor SecureStore {
    public let root: URL
    private let secrets: any SecretStore
    private let keyName: String
    public init(root: URL, secrets: any SecretStore = KeychainStore(), keyName: String = "device-vault") throws {
        self.root = root; self.secrets = secrets; self.keyName = keyName
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)
        // Tighten earlier ciphertext records without decrypting or rewriting them.
        for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where file.pathExtension == "rmrecord" {
            try BoundedFile.restrictPermissions(file)
        }
        var mutableRoot = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try mutableRoot.setResourceValues(values)
    }
    func key() throws -> Data {
        if let existing = try secrets.read(keyName) {
            guard existing.count == 32 else { throw RMError.missingKey }
            return existing
        }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard !files.contains(where: { $0.pathExtension == "rmrecord" }) else { throw RMError.missingKey }
        let value = try RecordCrypto.random(32)
        try secrets.write(value, account: keyName)
        return value
    }
    func location(_ id: String) throws -> URL {
        guard !id.isEmpty, id.utf8.count <= 1024 else { throw RMError.invalidInput }
        return root.appendingPathComponent(RecordCrypto.digest(Data(id.utf8))).appendingPathExtension("rmrecord")
    }
    public func save<T: Encodable & Sendable>(_ value: T, id: String) throws {
        let clear = try JSONEncoder().encode(value)
        guard clear.count <= 64 * 1024 * 1024 else { throw RMError.tooLarge }
        let encrypted = try RecordCrypto.seal(clear, key: key(), id: id)
        try writeCiphertext(encrypted, at: location(id))
    }
    public func load<T: Decodable & Sendable>(_ type: T.Type, id: String) throws -> T? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { _ = try key(); return nil }
        let encrypted = try boundedCiphertext(url,limit:90*1024*1024)
        return try JSONDecoder().decode(type, from: RecordCrypto.open(encrypted, key: key(), id: id))
    }
    public func delete(id: String) throws {
        _ = try key()
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    public func saveBytes(_ bytes: Data, id: String) throws {
        guard bytes.count <= 1024 * 1024 else { throw RMError.tooLarge }
        try writeCiphertext(RecordCrypto.seal(bytes, key: key(), id: id), at: location(id))
    }
    public func loadBytes(id: String) throws -> Data? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try RecordCrypto.open(boundedCiphertext(url,limit:2*1024*1024), key: key(), id: id)
    }
    /// Explicit authenticated wipe is also the recovery path after losing a device key.
    /// Device-key rotation uses encrypted backup, authenticated wipe, then import; there is no in-place rekeying.
    public func wipeRecords() throws {
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "rmrecord" {
            try FileManager.default.removeItem(at: url)
        }
        try secrets.delete(keyName)
    }
    private func writeCiphertext(_ data: Data, at url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func boundedCiphertext(_ url:URL,limit:Int) throws -> Data {
        try BoundedFile.read(url,limit:limit)
    }
}

public enum SecretEncryption {
    public static func sealedBox(_ value: Data, publicKeyBase64: String) throws -> String {
        guard value.count <= 48 * 1024, let key = Data(base64Encoded: publicKeyBase64), key.count == 32,
              let sealed = Sodium().box.seal(message: Array(value), recipientPublicKey: Array(key)) else { throw RMError.invalidInput }
        return Data(sealed).base64EncodedString()
    }
}
public struct BackupPayload: Codable, Sendable {
    public var version = 1; public var data: AppData; public var drafts: [WorkspaceDraft]; public var checkpoints: [Checkpoint]
    public init(data: AppData, drafts: [WorkspaceDraft], checkpoints: [Checkpoint]) { self.data = data; self.drafts = drafts; self.checkpoints = checkpoints }
}
public enum EncryptedBackup {
    private struct Bundle: Codable { var version = 1; var salt: Data; var sealed: Data }
    public static func export(_ payload: BackupPayload, passphrase: String) throws -> Data {
        guard passphrase.utf8.count >= 12, passphrase.utf8.count <= 1024 else { throw RMError.invalidInput }
        let salt = try RecordCrypto.random(16)
        let key = try derive(passphrase, salt: salt)
        return try JSONEncoder().encode(Bundle(salt: salt, sealed: RecordCrypto.seal(JSONEncoder().encode(payload), key: key, id: "portable-backup")))
    }
    public static func restore(_ bytes: Data, passphrase: String) throws -> BackupPayload {
        guard bytes.count <= 90 * 1024 * 1024, passphrase.utf8.count <= 1024 else { throw RMError.tooLarge }
        let bundle = try JSONDecoder().decode(Bundle.self, from: bytes)
        guard bundle.version == 1, bundle.salt.count == 16 else { throw RMError.corruptRecord }
        var payload = try JSONDecoder().decode(BackupPayload.self, from: RecordCrypto.open(bundle.sealed, key: derive(passphrase, salt: bundle.salt), id: "portable-backup"))
        guard payload.version == 1, payload.data.conversations.count <= 1000, payload.drafts.count <= 1000, payload.checkpoints.count <= 1000 else { throw RMError.corruptRecord }
        guard Set(payload.data.conversations.map(\.id)).count == payload.data.conversations.count,
              Set(payload.data.providers.map(\.id)).count == payload.data.providers.count,
              Set(payload.data.personas.map(\.id)).count == payload.data.personas.count,
              Set(payload.drafts.map(\.conversationID)).count == payload.drafts.count,
              Set(payload.checkpoints.map(\.id)).count == payload.checkpoints.count else { throw RMError.corruptRecord }
        // Imports retain edits but deliberately invalidate all previous connection identities.
        payload.data.accounts = []
        payload.data.preferences.syncHistory = false; payload.data.preferences.webEnabled = false
        payload.data.preferences.webConsentEndpoint = nil
        for i in payload.data.providers.indices {
            payload.data.providers[i].consentEndpoint = nil; payload.data.providers[i].privacyConsentedModels = nil
            if payload.data.providers[i].usesChatGPT { payload.data.providers[i].chatGPTAccount = nil; payload.data.providers[i].models = [] }
        }
        var connections: [UUID:UUID] = [:]
        func newConnection(_ old:UUID) -> UUID { if let id = connections[old] { return id }; let id = UUID(); connections[old] = id; return id }
        for i in payload.drafts.indices { payload.drafts[i].scope.connectionID = newConnection(payload.drafts[i].scope.connectionID); payload.drafts[i].revision = UUID() }
        for i in payload.checkpoints.indices { payload.checkpoints[i].draft.scope.connectionID = newConnection(payload.checkpoints[i].draft.scope.connectionID); payload.checkpoints[i].draft.revision = UUID() }
        for i in payload.data.conversations.indices {
            if let scope = payload.data.conversations[i].repository { payload.data.conversations[i].repository?.connectionID = newConnection(scope.connectionID) }
        }
        return payload
    }
    private static func derive(_ passphrase: String, salt: Data) throws -> Data {
        let sodium = Sodium()
        guard let key = sodium.pwHash.hash(outputLength: 32, passwd: Array(passphrase.utf8), salt: Array(salt),
            opsLimit: sodium.pwHash.OpsLimitInteractive, memLimit: sodium.pwHash.MemLimitInteractive, alg: .Argon2ID13) else { throw RMError.unavailable }
        return Data(key)
    }
}

public enum BackupImport {
    /// Import as independent conversations and profiles; existing credentials and consent cannot attach by UUID collision.
    public static func prepare(_ payload:BackupPayload) -> BackupPayload {
        var imported = payload
        let conversationIDs = Dictionary(payload.data.conversations.map { ($0.id,UUID()) },uniquingKeysWith:{ a,_ in a })
        let providerIDs = Dictionary(payload.data.providers.map { ($0.id,UUID()) },uniquingKeysWith:{ a,_ in a })
        let personaIDs = Dictionary(payload.data.personas.map { ($0.id,UUID()) },uniquingKeysWith:{ a,_ in a })
        for i in imported.data.providers.indices {
            imported.data.providers[i].id = providerIDs[imported.data.providers[i].id]!; imported.data.providers[i].consentEndpoint = nil
            if imported.data.providers[i].usesChatGPT { imported.data.providers[i].chatGPTAccount = nil; imported.data.providers[i].models = [] }
        }
        for i in imported.data.personas.indices { imported.data.personas[i].id = personaIDs[imported.data.personas[i].id]! }
        for i in imported.data.macros.indices { imported.data.macros[i].id = UUID() }
        for i in imported.data.conversations.indices {
            let c = imported.data.conversations[i]
            imported.data.conversations[i].id = conversationIDs[c.id]!
            imported.data.conversations[i].title += " (import)"
            imported.data.conversations[i].providerID = c.providerID.flatMap { providerIDs[$0] }
            imported.data.conversations[i].personaID = c.personaID.flatMap { personaIDs[$0] }
            // A bundle is not origin-authenticated. Replay its history only as visible user/assistant turns: system rows,
            // raw protocol rounds and provider state would reach the request verbatim. ConversationContext rebuilds
            // tool history from calls/results with the untrusted-data framing.
            imported.data.conversations[i].messages = c.messages.filter { $0.role == .user || $0.role == .assistant }.map {
                var m = $0; m.protocolRounds = nil; m.providerContinuation = nil; return m
            }
        }
        imported.drafts = imported.drafts.compactMap { d in guard let id = conversationIDs[d.conversationID] else { return nil }; var copy = d; copy.conversationID = id; return copy }
        imported.checkpoints = imported.checkpoints.compactMap { c in guard let id = conversationIDs[c.draft.conversationID] else { return nil }; var copy = c; copy.id = UUID(); copy.draft.conversationID = id; return copy }
        imported.data.tombstones = [:]; return imported
    }
}
