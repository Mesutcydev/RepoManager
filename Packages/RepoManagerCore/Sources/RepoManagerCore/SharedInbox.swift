import Foundation
import CryptoKit

public struct SharePayload: Codable, Sendable {
    public var text: String; public var name: String; public var document: Data?
    public init(text: String, name: String, document: Data? = nil) { self.text = text; self.name = name; self.document = document }
}
public struct SharedInboxEnvelope: Codable, Sendable {
    public var version = 1; public var id = UUID(); public var ephemeralPublicKey: Data; public var ciphertext: Data
}
public enum SharedInbox {
    public static let group = "group.com.mesutcydev.repomanager"
    private static let keyName = "share-inbox-private-key"
    public static func prepare(root: URL, secrets: any SecretStore = KeychainStore()) throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:root.path)
        let key: Curve25519.KeyAgreement.PrivateKey
        if let value = try secrets.read(keyName) { key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:value) }
        else {
            let existing = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            guard !existing.contains(where:{ $0.pathExtension == "rminbox" }) else { throw RMError.missingKey }
            key = Curve25519.KeyAgreement.PrivateKey(); try secrets.write(key.rawRepresentation,account:keyName)
        }
        // This is public key material; the extension never receives a private key or account credentials.
        try key.publicKey.rawRepresentation.write(to:root.appendingPathComponent("public-key"),options:.atomic)
    }
    public static func encrypt(_ payload: SharePayload, publicKey: Data) throws -> SharedInboxEnvelope {
        guard payload.name.utf8.count <= 255,payload.text.utf8.count <= 128*1024, (payload.document?.count ?? 0) <= 32*1024*1024 else { throw RMError.tooLarge }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let recipient = try Curve25519.KeyAgreement.PublicKey(rawRepresentation:publicKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with:recipient)
        let key = shared.hkdfDerivedSymmetricKey(using:SHA256.self,salt:Data("RepoManagerShare:1".utf8),sharedInfo:Data(),outputByteCount:32)
        var e = SharedInboxEnvelope(ephemeralPublicKey:ephemeral.publicKey.rawRepresentation,ciphertext:Data())
        e.ciphertext = try RecordCrypto.seal(JSONEncoder().encode(payload),key:key.withUnsafeBytes { Data($0) },id:e.id.uuidString)
        return e
    }
    public static func receive(root: URL, secrets: any SecretStore = KeychainStore()) throws -> [(URL,SharePayload)] {
        guard let raw = try secrets.read(keyName) else { throw RMError.missingKey }
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:raw)
        let files = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension == "rminbox" }
        guard files.count <= 100 else { throw RMError.tooLarge }
        var combinedBytes = 0
        return try files.map { url in
            let data = try BoundedFile.read(url,limit:min(48*1024*1024,64*1024*1024-combinedBytes)); combinedBytes += data.count
            let e = try JSONDecoder().decode(SharedInboxEnvelope.self,from:data); guard e.version == 1 else { throw RMError.corruptRecord }
            let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation:e.ephemeralPublicKey)
            let shared = try key.sharedSecretFromKeyAgreement(with:pub)
            let symmetric = shared.hkdfDerivedSymmetricKey(using:SHA256.self,salt:Data("RepoManagerShare:1".utf8),sharedInfo:Data(),outputByteCount:32)
            let payload = try JSONDecoder().decode(SharePayload.self,from:RecordCrypto.open(e.ciphertext,key:symmetric.withUnsafeBytes { Data($0) },id:e.id.uuidString))
            guard payload.name.utf8.count <= 255,payload.text.utf8.count <= 128*1024,(payload.document?.count ?? 0) <= 32*1024*1024 else { throw RMError.tooLarge }
            return (url,payload)
        }
    }
}
