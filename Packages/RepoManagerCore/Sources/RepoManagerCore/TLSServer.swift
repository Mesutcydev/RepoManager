import Foundation
import Security
import Network
import CryptoKit

public final class TLSIdentity: @unchecked Sendable {
    private let label: String
    private let tag: Data
    private let lock = NSLock()
    public init(namespace:String = "com.mesutcydev.repomanager.tls") {
        label = namespace+".certificate"; tag = Data((namespace+".private-key").utf8)
    }
    public struct Material: @unchecked Sendable { public var identity: SecIdentity; public var certificate: Data; public var fingerprint: String }
    public func loadOrCreate(host: String) throws -> Material {
        lock.lock(); defer { lock.unlock() }
        guard !host.isEmpty, host.count <= 200, !host.contains("/"), !host.contains(":"), host.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || ".-".unicodeScalars.contains($0) }) else { throw RMError.invalidInput }
        if let identity = try load(), let material = try material(identity), valid(material.certificate,host:host) { return material }
        // Explicit server enablement is the only path that issues or rotates this app's identity.
        try removeOwned()
        var error: Unmanaged<CFError>?
        let privateAttrs: [String:Any] = [kSecAttrIsPermanent as String:true,kSecAttrApplicationTag as String:tag,
            kSecAttrLabel as String:label,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var attrs: [String:Any] = [kSecAttrKeyType as String:kSecAttrKeyTypeECSECPrimeRandom,kSecAttrKeySizeInBits as String:256,kSecPrivateKeyAttrs as String:privateAttrs,kSecUseDataProtectionKeychain as String:true]
        var key: SecKey?
        #if !targetEnvironment(simulator)
        if let access = SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenUnlockedThisDeviceOnly,.privateKeyUsage,&error) {
            var protected = privateAttrs; protected[kSecAttrAccessible as String] = nil; protected[kSecAttrAccessControl as String] = access
            attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave; attrs[kSecPrivateKeyAttrs as String] = protected
            key = SecKeyCreateRandomKey(attrs as CFDictionary,&error)
        }
        #endif
        if key == nil { error = nil; attrs[kSecAttrTokenID as String] = nil; attrs[kSecPrivateKeyAttrs as String] = privateAttrs; key = SecKeyCreateRandomKey(attrs as CFDictionary,&error) }
        guard let key, let pub = SecKeyCopyPublicKey(key), let bytes = SecKeyCopyExternalRepresentation(pub,&error) as Data? else { throw RMError.locked }
        let tbs = try Self.certificateBody(publicKey:Array(bytes),host:host)
        guard let signature = SecKeyCreateSignature(key,.ecdsaSignatureMessageX962SHA256,Data(tbs) as CFData,&error) as Data? else { throw RMError.unavailable }
        let der = Data(DER.sequence(tbs + DER.sequence(DER.oid([0x2a,0x86,0x48,0xce,0x3d,0x04,0x03,0x02])) + DER.bitString(Array(signature))))
        guard let cert = SecCertificateCreateWithData(nil,der as CFData) else { throw RMError.corruptRecord }
        let status = SecItemAdd([kSecClass as String:kSecClassCertificate,kSecValueRef as String:cert,
            kSecAttrLabel as String:label,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly,kSecUseDataProtectionKeychain as String:true] as CFDictionary,nil)
        guard status == errSecSuccess, let identity = SecIdentityCreate(nil,cert,key), let result = try material(identity), valid(result.certificate,host:host) else { throw RMError.locked }
        return result
    }
    public func removeOwned() throws {
        for q: [String:Any] in [[kSecClass as String:kSecClassCertificate,kSecAttrLabel as String:label],
                               [kSecClass as String:kSecClassKey,kSecAttrApplicationTag as String:tag]] {
            var query = q; query[kSecUseDataProtectionKeychain as String] = true
            let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw RMError.locked }
        }
    }
    private func load() throws -> SecIdentity? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass as String:kSecClassCertificate,kSecAttrLabel as String:label,
            kSecReturnRef as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseDataProtectionKeychain as String:true] as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let result, CFGetTypeID(result) == SecCertificateGetTypeID() else { throw RMError.locked }
        let certificate = result as! SecCertificate
        var privateKey:CFTypeRef?
        let keyStatus = SecItemCopyMatching([kSecClass as String:kSecClassKey,kSecAttrApplicationTag as String:tag,
            kSecReturnRef as String:true,kSecMatchLimit as String:kSecMatchLimitOne,kSecUseDataProtectionKeychain as String:true] as CFDictionary,&privateKey)
        if keyStatus == errSecItemNotFound { return nil }
        guard keyStatus == errSecSuccess,let privateKey,CFGetTypeID(privateKey) == SecKeyGetTypeID(),
              let identity = SecIdentityCreate(nil,certificate,privateKey as! SecKey) else { throw RMError.locked }
        return identity
    }
    private func material(_ identity: SecIdentity) throws -> Material? {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity,&certificate) == errSecSuccess, let certificate else { throw RMError.locked }
        let data = SecCertificateCopyData(certificate) as Data
        return Material(identity:identity,certificate:data,fingerprint:RecordCrypto.digest(data))
    }
    public func valid(_ data: Data, host: String) -> Bool {
        guard let cert = SecCertificateCreateWithData(nil,data as CFData) else { return false }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(cert,SecPolicyCreateSSL(true,host as CFString),&trust) == errSecSuccess, let trust else { return false }
        SecTrustSetAnchorCertificates(trust,[cert] as CFArray); SecTrustSetAnchorCertificatesOnly(trust,true)
        SecTrustSetNetworkFetchAllowed(trust,false)
        return SecTrustEvaluateWithError(trust,nil)
    }
    static func certificateBody(publicKey: [UInt8], host: String) throws -> [UInt8] {
        let signature = DER.sequence(DER.oid([0x2a,0x86,0x48,0xce,0x3d,0x04,0x03,0x02]))
        let name = DER.sequence(DER.set(DER.sequence(DER.oid([0x55,0x04,0x03])+DER.utf8String(host))))
        var serial = Array(try RecordCrypto.random(16)); serial[0] &= 0x7f; if serial[0] == 0 { serial[0] = 1 }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0); formatter.dateFormat = "yyMMddHHmmss'Z'"
        let validity = DER.sequence(DER.utcTime(formatter.string(from:Date().addingTimeInterval(-300)))+DER.utcTime(formatter.string(from:Date().addingTimeInterval(30*86400))))
        let spki = DER.sequence(DER.sequence(DER.oid([0x2a,0x86,0x48,0xce,0x3d,0x02,0x01])+DER.oid([0x2a,0x86,0x48,0xce,0x3d,0x03,0x01,0x07]))+DER.bitString(publicKey))
        var san = DER.tlv(tag:0x82,Array(host.utf8))
        var address = in_addr()
        if inet_pton(AF_INET,host,&address) == 1 { san = withUnsafeBytes(of:address) { DER.tlv(tag:0x87,Array($0)) } }
        if host == "localhost" { san += DER.tlv(tag:0x87,[127,0,0,1]) }
        let names = DER.sequence(DER.oid([0x55,0x1d,0x11])+DER.tlv(tag:0x04,DER.sequence(san)))
        let basic = DER.sequence(DER.oid([0x55,0x1d,0x13])+DER.tlv(tag:0x01,[0xff])+DER.tlv(tag:0x04,DER.sequence([])))
        let usage = DER.sequence(DER.oid([0x55,0x1d,0x0f])+DER.tlv(tag:0x01,[0xff])+DER.tlv(tag:0x04,DER.tlv(tag:0x03,[0x07,0x80])))
        let extended = DER.sequence(DER.oid([0x55,0x1d,0x25])+DER.tlv(tag:0x04,DER.sequence(DER.oid([0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x01]))))
        let extensions = DER.contextExplicit(tag:3,DER.sequence(names+basic+usage+extended))
        return DER.sequence(DER.contextExplicit(tag:0,DER.integer([2]))+DER.integer(serial)+signature+name+validity+name+spki+extensions)
    }
    public static func pem(_ data: Data) -> String {
        let base64 = data.base64EncodedString(); var rows: [String] = []; var i = base64.startIndex
        while i < base64.endIndex { let end = base64.index(i,offsetBy:64,limitedBy:base64.endIndex) ?? base64.endIndex; rows.append(String(base64[i..<end])); i = end }
        return "-----BEGIN CERTIFICATE-----\n"+rows.joined(separator:"\n")+"\n-----END CERTIFICATE-----\n"
    }
}

public struct HTTPRequestParser: Sendable {
    private var data = Data()
    public init() {}
    public mutating func feed(_ bytes: Data) throws -> APIRequest? {
        data.append(bytes); guard data.count <= 1024*1024+16384 else { throw RMError.tooLarge }
        guard let end = data.range(of:Data([13,10,13,10])) else { guard data.count <= 16384 else { throw RMError.tooLarge }; return nil }
        guard end.lowerBound <= 16384, let text = String(data:data.prefix(end.lowerBound),encoding:.utf8) else { throw RMError.invalidInput }
        let lines = text.components(separatedBy:"\r\n"); let first = lines[0].split(separator:" ").map(String.init)
        guard first.count == 3, ["GET","POST"].contains(first[0]), first[2] == "HTTP/1.1", first[1].hasPrefix("/"), first[1].count <= 2048 else { throw RMError.invalidInput }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of:":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { throw RMError.invalidInput }
            let key = String(line[..<colon]).lowercased(); let value = String(line[line.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
            guard !key.isEmpty,headers[key] == nil,key.utf8.allSatisfy({ (97...122).contains($0) || $0 == 45 }),
                  value.utf8.count <= 4096,!value.unicodeScalars.contains(where:{ $0.value < 32 || $0.value == 127 }) else { throw RMError.invalidInput }
            headers[key] = value
        }
        guard headers["transfer-encoding"] == nil,headers["host"]?.isEmpty == false else { throw RMError.invalidInput }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        guard length >= 0, length <= 1024*1024, headers["content-length"] == nil || String(length) == headers["content-length"] else { throw RMError.invalidInput }
        let bodyStart = end.upperBound
        guard data.count >= bodyStart+length else { return nil }
        guard data.count == bodyStart+length else { throw RMError.invalidInput } // No pipelining/smuggling.
        if first[0] == "POST" { guard headers["content-type"]?.split(separator:";",maxSplits:1).first?.trimmingCharacters(in:.whitespaces).lowercased() == "application/json" else { throw RMError.invalidInput } }
        return APIRequest(method:first[0],path:first[1],headers:headers,body:data.subdata(in:bodyStart..<data.count))
    }
}
public actor HTTPSServer {
    private let api: AgentAPI; private let identity: TLSIdentity
    private var listener: NWListener?; private var connections: [UUID:NWConnection] = [:]
    private var startGate: ListenerStartGate?
    public nonisolated let status: AsyncStream<Bool>
    private let statusOutput: AsyncStream<Bool>.Continuation
    private var tasks: [UUID:Task<Void,Never>] = [:]; private let queue = DispatchQueue(label:"com.mesutcydev.repomanager.https")
    public init(api: AgentAPI, identity: TLSIdentity = TLSIdentity()) {
        self.api = api; self.identity = identity
        let pair = AsyncStream<Bool>.makeStream(bufferingPolicy:.bufferingNewest(1)); status = pair.stream; statusOutput = pair.continuation
    }
    public func start(host: String, port: UInt16 = 11435) async throws -> TLSIdentity.Material {
        guard listener == nil else { throw RMError.conflict }; guard port > 0 else { throw RMError.invalidInput }
        let material = try identity.loadOrCreate(host:host)
        guard let sec = sec_identity_create(material.identity) else { throw RMError.unavailable }
        let tls = NWProtocolTLS.Options(); sec_protocol_options_set_local_identity(tls.securityProtocolOptions,sec)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        let parameters = NWParameters(tls:tls,tcp:NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .hostPort(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!)
        parameters.allowLocalEndpointReuse = false
        // The scoped endpoint already carries the port; passing it again makes
        // Network.framework reject the listener with EINVAL.
        let listener = try NWListener(using:parameters)
        listener.newConnectionHandler = { [weak self] connection in Task { await self?.accept(connection) } }
        let gate = ListenerStartGate(); self.startGate = gate; self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: gate.finish(.success(()))
            case .failed: gate.finish(.failure(RMError.connection)); Task { await self?.failed(listener) }
            case .cancelled: gate.finish(.failure(RMError.cancelled))
            default: break
            }
        }
        let timeout = Task { do { try await Task.sleep(for:.seconds(10)); gate.finish(.failure(RMError.connection)); listener.cancel() } catch {} }
        defer { timeout.cancel() }
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { gate.install($0); listener.start(queue:queue) }
            } onCancel: { gate.finish(.failure(RMError.cancelled)); listener.cancel() }
            guard self.listener === listener else { throw RMError.cancelled }
            startGate = nil; statusOutput.yield(true); return material
        } catch { if self.listener === listener { await stop() }; throw error }
    }
    private func failed(_ candidate:NWListener) async {
        if listener === candidate { await stop() }
    }
    public func stop() async {
        startGate?.finish(.failure(RMError.cancelled)); startGate = nil; statusOutput.yield(false)
        listener?.cancel(); listener = nil; for connection in connections.values { connection.cancel() }; connections.removeAll()
        for task in tasks.values { task.cancel() }; tasks.removeAll(); await api.stop()
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 16 else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection; connection.start(queue:queue)
        tasks[id] = Task {
            do {
                // A timeout also covers stalled TLS handshakes and incomplete headers/bodies.
                let request = try await withThrowingTaskGroup(of:APIRequest.self) { group in
                    group.addTask {
                        var parser = HTTPRequestParser()
                        while true { let data = try await Self.receive(connection); if let request = try parser.feed(data) { return request } }
                    }
                    group.addTask { try await Task.sleep(for:.seconds(20)); connection.cancel(); throw RMError.connection }
                    guard let first = try await group.next() else { throw RMError.connection }; group.cancelAll(); return first
                }
                let source: String
                if case .hostPort(let host,_) = connection.endpoint { source = String(describing:host) } else { source = "local" }
                let response = await api.handle(request,source:source)
                try await Self.send(connection,Data("HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Response")\r\nContent-Type: \(response.contentType)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n".utf8)+Data((response.stream == nil ? "Content-Length: \(response.body.count)\r\n\r\n" : "\r\n").utf8))
                if let stream = response.stream { for try await chunk in stream { try Task.checkCancellation(); try await Self.send(connection,chunk) } }
                else { try await Self.send(connection,response.body) }
            } catch { /* Do not log requests, body, headers, tokens or upstream errors. */ }
            connection.cancel(); self.connections[id] = nil; self.tasks[id] = nil
        }
    }
    private static func receive(_ c: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            c.receive(minimumIncompleteLength:1,maximumLength:16384) { data,_,complete,error in
                if error != nil { continuation.resume(throwing:RMError.connection) }
                else if let data, !data.isEmpty { continuation.resume(returning:data) }
                else if complete { continuation.resume(throwing:RMError.cancelled) }
                else { continuation.resume(throwing:RMError.connection) }
            }
        }
    }
    private static func send(_ c: NWConnection, _ data: Data) async throws {
        // A peer that stops reading must not hold one of the 16 slots: cancelling the connection fails the pending send.
        let watchdog = Task { try await Task.sleep(for:.seconds(30)); c.cancel() }
        defer { watchdog.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            c.send(content:data,completion:.contentProcessed { error in if error != nil { continuation.resume(throwing:RMError.connection) } else { continuation.resume() } })
        }
    }
}
private final class ListenerStartGate: @unchecked Sendable {
    private let lock = NSLock(); private var continuation: CheckedContinuation<Void,Error>?
    private var result: Result<Void,Error>?
    func install(_ value:CheckedContinuation<Void,Error>) {
        lock.lock(); if let result { lock.unlock(); value.resume(with:result) } else { continuation = value; lock.unlock() }
    }
    func finish(_ value:Result<Void,Error>) {
        lock.lock(); guard result == nil else { lock.unlock(); return }
        result = value; let waiting = continuation; continuation = nil; lock.unlock(); waiting?.resume(with:value)
    }
}
