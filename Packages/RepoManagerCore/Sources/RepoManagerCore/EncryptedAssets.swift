import Foundation
import CryptoKit

public struct EncryptedAsset: Codable, Sendable, Identifiable {
    public var id = UUID(); public var name: String; public var byteCount: Int; public var sha256: String; public var chunks: Int
    public var ownerID: UUID?
    public init(name: String, byteCount: Int, sha256: String, chunks: Int, id: UUID) { self.id = id; self.name = name; self.byteCount = byteCount; self.sha256 = sha256; self.chunks = chunks }
}
/// The HTTPS transport pulls one decrypted 1-MiB chunk at a time. No clear file exists.
public final class EncryptedAssetStream: InputStream, @unchecked Sendable {
    private let urls: [URL]; private let key: Data; private let ids: [String]
    private var index = 0; private var chunk = Data(); private var offset = 0; private var state: Stream.Status = .notOpen
    private let lock = NSLock(); private var failure: Error?
    init(urls: [URL], key: Data, ids: [String]) { self.urls = urls; self.key = key; self.ids = ids; super.init(data:Data()) }
    public override func open() { lock.withLock { state = .open } }
    public override func close() { lock.withLock { chunk.resetBytes(in:0..<chunk.count); chunk.removeAll(); state = .closed } }
    public override var streamStatus: Stream.Status { lock.withLock { state } }
    public override var streamError: Error? { lock.withLock { failure } }
    public override var hasBytesAvailable: Bool { lock.withLock { offset < chunk.count || index < urls.count } }
    public override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        lock.withLock {
            guard state == .open, len > 0 else { return state == .error ? -1 : 0 }
            do {
                if offset == chunk.count {
                    chunk.resetBytes(in:0..<chunk.count); chunk.removeAll(); offset = 0
                    guard index < urls.count else { state = .atEnd; return 0 }
                    let cipher = try BoundedFile.read(urls[index],limit:2*1024*1024)
                    chunk = try RecordCrypto.open(cipher,key:key,id:ids[index]); index += 1
                }
                let count = min(len,chunk.count-offset)
                chunk.copyBytes(to:buffer,from:offset..<offset+count); offset += count; return count
            } catch { failure = RMError.corruptRecord; state = .error; return -1 }
        }
    }
    public override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool { false }
    public override func schedule(in aRunLoop: RunLoop,forMode mode: RunLoop.Mode) {}
    public override func remove(from aRunLoop: RunLoop,forMode mode: RunLoop.Mode) {}
}

extension SecureStore {
    public func assetStream(_ asset: EncryptedAsset) throws -> sending EncryptedAssetStream {
        guard asset.chunks > 0, asset.chunks <= 50, asset.byteCount <= 50*1024*1024 else { throw RMError.tooLarge }
        let ids = (0..<asset.chunks).map { "asset:\(asset.id):\($0)" }
        return try EncryptedAssetStream(urls:ids.map(location),key:key(),ids:ids)
    }
    public func importAsset(_ url: URL, ownerID: UUID? = nil) throws -> EncryptedAsset {
        let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
        let id = UUID(); var count = 0, chunks = 0; var hash = SHA256()
        do {
            while let data = try file.read(upToCount:1024*1024), !data.isEmpty {
                count += data.count; guard count <= 50*1024*1024 else { throw RMError.tooLarge }
                hash.update(data:data); try saveBytes(data,id:"asset:\(id):\(chunks)"); chunks += 1
            }
            guard chunks > 0 else { throw RMError.invalidInput }
            var asset = EncryptedAsset(name:url.lastPathComponent,byteCount:count,sha256:hash.finalize().map { String(format:"%02x",$0) }.joined(),chunks:chunks,id:id); asset.ownerID = ownerID
            try save(asset,id:"asset-metadata:\(id)"); return asset
        } catch { for i in 0..<chunks { try? delete(id:"asset:\(id):\(i)") }; throw error }
    }
    public func storeAsset(_ stream: AsyncThrowingStream<Data,Error>, name: String, ownerID: UUID? = nil) async throws -> EncryptedAsset {
        let id = UUID(); var buffer = Data(); var count = 0, chunks = 0; var hash = SHA256()
        do {
            for try await data in stream {
                try Task.checkCancellation(); count += data.count; guard count <= 50*1024*1024 else { throw RMError.tooLarge }
                hash.update(data:data); buffer.append(data)
                while buffer.count >= 1024*1024 { try saveBytes(Data(buffer.prefix(1024*1024)),id:"asset:\(id):\(chunks)"); chunks += 1; buffer.removeFirst(1024*1024) }
            }
            if !buffer.isEmpty { try saveBytes(buffer,id:"asset:\(id):\(chunks)"); chunks += 1 }
            guard chunks > 0 else { throw RMError.invalidInput }
            var asset = EncryptedAsset(name:name,byteCount:count,sha256:hash.finalize().map { String(format:"%02x",$0) }.joined(),chunks:chunks,id:id); asset.ownerID = ownerID
            try save(asset,id:"asset-metadata:\(id)"); return asset
        } catch { for i in 0..<chunks { try? delete(id:"asset:\(id):\(i)") }; throw error }
    }
    public func asset(_ id: UUID) throws -> EncryptedAsset? { try load(EncryptedAsset.self,id:"asset-metadata:\(id)") }
}

extension GitHubClient {
    public func download(scope: RepositoryScope, kind: String, id: Int) async throws -> EncryptedAsset {
        guard id > 0, ["artifact","job_log"].contains(kind) else { throw RMError.invalidInput }
        _ = try await verify(scope)
        let path = repo(scope)+(kind == "artifact" ? "/actions/artifacts/\(id)/zip" : "/actions/jobs/\(id)/logs")
        let token = try await connections.token(for:scope)
        var request = URLRequest(url:try URLPolicy.append(URL(string:"https://api.github.com")!,segments:path.split(separator:"/").map(String.init)))
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
        let r = try await transport.send(request,limit:1024*1024)
        let source: URLRequest
        if r.status == 302 {
            guard let location = r.headers["location"], let url = URL(string:location), let host = url.host?.lowercased(),
                  host.hasSuffix(".actions.githubusercontent.com") || host.hasSuffix(".blob.core.windows.net") || host == "objects.githubusercontent.com" else { throw RMError.insecureURL }
            try URLPolicy.validate(url); source = URLRequest(url:url) // No bearer forwarded to a signed download URL.
        } else {
            try SecureHTTPTransport.checkStatus(r.status)
            return try await vault.storeAsset(AsyncThrowingStream { c in c.yield(r.data); c.finish() },name:"\(kind)-\(id)"+(kind == "artifact" ? ".zip" : ".txt"))
        }
        return try await vault.storeAsset(transport.stream(source,limit:50*1024*1024),name:"\(kind)-\(id)"+(kind == "artifact" ? ".zip" : ".txt"))
    }
    func uploadAsset(_ asset: EncryptedAsset, releaseID: Int, scope: RepositoryScope, validate:@escaping @Sendable () async throws -> Void) async throws -> JSON {
        guard releaseID > 0 else { throw RMError.invalidInput }
        _ = try InputValidation.path(asset.name)
        let token = try await connections.token(for:scope)
        let url = try URLPolicy.append(URL(string:"https://uploads.github.com")!,segments:["repos",scope.owner,scope.name,"releases",String(releaseID),"assets"],query:["name":asset.name])
        var request = URLRequest(url:url); request.httpMethod = "POST"; request.httpBodyStream = try await vault.assetStream(asset)
        request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization"); request.setValue("application/octet-stream",forHTTPHeaderField:"Content-Type")
        request.setValue(String(asset.byteCount),forHTTPHeaderField:"Content-Length")
        try await validate()
        do {
            let r = try await transport.send(request,limit:1024*1024)
            if r.status >= 500 || r.status == 408 { throw RMError.uncertainWrite }
            try SecureHTTPTransport.checkStatus(r.status)
            guard let result = try? JSON.parse(r.data),result["id"].int != nil else { throw RMError.uncertainWrite }
            return GitHubRedaction.clean(result)
        }
        catch let e as RMError { if [.connection,.cancelled,.tooLarge,.corruptRecord].contains(e) { throw RMError.uncertainWrite }; throw e }
    }
}
