import Foundation
import Network
import Security

final class HTTPAccumulator:@unchecked Sendable {
    private let lock = NSLock(); private var bytes = Data(); private let limit:Int
    init(limit:Int) { self.limit = limit }
    var data:Data { lock.withLock { bytes } }
    func append(_ data:Data) throws { try lock.withLock { guard bytes.count+data.count <= limit else { throw RMError.tooLarge }; bytes.append(data) } }
}

/// Strict HTTP/1.1 framing. It rejects ambiguous lengths and caps headers, trailers and bodies.
struct HTTPResponseFramer:Sendable {
    struct Head:Sendable { var status:Int; var headers:[String:String] }
    private enum Body:Sendable { case length(Int),chunked,close }
    private var buffer = Data(); private var body:Body?; private var chunkRemaining:Int?; private var needsCRLF = false
    private var trailers = false; private var total = 0; private var interim = 0
    private let limit:Int
    private(set) var head:Head?; private(set) var complete = false
    init(limit:Int) { self.limit = limit }
    private mutating func discard(_ count:Int) { buffer = Data(buffer.dropFirst(count)) }
    mutating func feed(_ data:Data,eof:Bool = false) throws -> [Data] {
        guard !complete || data.isEmpty else { throw RMError.invalidInput }
        buffer.append(data); var output:[Data] = []
        if head == nil {
            while head == nil {
                guard let range = buffer.range(of:Data([13,10,13,10])) else { guard buffer.count <= 16384,!eof else { throw RMError.connection }; return [] }
                guard range.lowerBound <= 16384,let text = String(data:buffer.prefix(range.lowerBound),encoding:.utf8) else { throw RMError.invalidInput }
                discard(range.upperBound)
                let lines = text.components(separatedBy:"\r\n"), statusLine = lines[0].split(separator:" ")
                guard statusLine.count >= 2,["HTTP/1.1","HTTP/1.0"].contains(String(statusLine[0])),let status = Int(statusLine[1]),(100...599).contains(status) else { throw RMError.invalidInput }
                var headers:[String:String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of:":"),colon != line.startIndex else { throw RMError.invalidInput }
                    let name = String(line[..<colon]).lowercased(), value = String(line[line.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
                    guard name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                          !value.contains("\r"),!value.contains("\n"),!value.contains("\0") else { throw RMError.invalidInput }
                    if ["content-length","transfer-encoding","content-encoding"].contains(name),headers[name] != nil { throw RMError.invalidInput }
                    if name != "set-cookie" { headers[name] = value }
                }
                if (100...199).contains(status) { interim += 1; guard status != 101,interim <= 4 else { throw RMError.unsupported }; continue }
                guard headers["content-length"] == nil || headers["transfer-encoding"] == nil,
                      headers["content-encoding"] == nil || headers["content-encoding"]?.lowercased() == "identity" else { throw RMError.unsupported }
                head = Head(status:status,headers:headers)
                if status == 204 || status == 304 { body = .length(0) }
                else if let encoding = headers["transfer-encoding"] { guard encoding.lowercased() == "chunked" else { throw RMError.unsupported }; body = .chunked }
                else if let length = headers["content-length"] { guard let value = Int(length),value >= 0,value <= limit else { throw RMError.tooLarge }; body = .length(value) }
                else { body = .close }
            }
        }
        func checked(_ data:Data) throws -> Data { guard total+data.count <= limit else { throw RMError.tooLarge }; return data }
        switch body {
        case .length(let remaining):
            let count = min(remaining,buffer.count), bytes = try checked(Data(buffer.prefix(count))); total += count
            if !bytes.isEmpty { output.append(bytes) }; discard(count); body = .length(remaining-count)
            if remaining == count { guard buffer.isEmpty else { throw RMError.invalidInput }; complete = true }
        case .close:
            if !buffer.isEmpty { let bytes = try checked(buffer); total += bytes.count; output.append(bytes); buffer.removeAll(keepingCapacity:true) }
            complete = eof
        case .chunked:
            while true {
                if trailers {
                    if buffer.starts(with:[13,10]) { discard(2); complete = true }
                    else if let end = buffer.range(of:Data([13,10,13,10])) { guard end.lowerBound <= 16384 else { throw RMError.tooLarge }; discard(end.upperBound); complete = true }
                    else { guard buffer.count <= 16384 else { throw RMError.tooLarge }; break }
                    guard buffer.isEmpty else { throw RMError.invalidInput }; break
                }
                if needsCRLF {
                    guard buffer.count >= 2 else { break }
                    guard buffer.starts(with:[13,10]) else { throw RMError.invalidInput }; discard(2); needsCRLF = false
                }
                if chunkRemaining == nil {
                    guard let end = buffer.range(of:Data([13,10])) else { guard buffer.count <= 4096 else { throw RMError.tooLarge }; break }
                    guard end.lowerBound <= 4096,let line = String(data:buffer.prefix(end.lowerBound),encoding:.ascii),
                          let number = line.split(separator:";",maxSplits:1).first,!number.isEmpty,number.allSatisfy(\.isHexDigit),
                          let size = Int(number,radix:16),size >= 0,total+size <= limit else { throw RMError.invalidInput }
                    discard(end.upperBound)
                    if size == 0 { trailers = true; continue }; chunkRemaining = size
                }
                guard let remaining = chunkRemaining,!buffer.isEmpty else { break }
                let count = min(remaining,buffer.count),bytes = try checked(Data(buffer.prefix(count))); total += count
                output.append(bytes); discard(count); chunkRemaining = remaining-count
                if chunkRemaining == 0 { chunkRemaining = nil; needsCRLF = true }
            }
        case nil: throw RMError.connection
        }
        if eof,!complete { throw RMError.connection }
        return output
    }
}

enum PinnedHTTPS {
    static func exchange(_ request:URLRequest,limit:Int,checkStatus:Bool,onResponse:@escaping @Sendable (HTTPResult) throws -> Void = { _ in },emit:@escaping @Sendable (Data) throws -> Void) async throws -> HTTPResult {
        guard let url = request.url,let host = url.host,limit > 0,limit <= 50*1024*1024 else { throw RMError.invalidInput }
        let addresses = try await URLPolicy.resolvePublic(url)
        guard let ip = addresses.first else { throw RMError.connection }
        let channel = try TLSChannel(ip:ip,hostname:host)
        let timeout = Task { do { try await Task.sleep(for:.seconds(300)); channel.cancel() } catch {} }
        defer { timeout.cancel(); channel.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation(); try await channel.connect()
            var components = URLComponents(url:url,resolvingAgainstBaseURL:false)
            components?.scheme = nil; components?.host = nil; components?.port = nil
            let path = (components?.percentEncodedPath.isEmpty == false ? components?.percentEncodedPath : "/") ?? "/"
            let target = path+(components?.percentEncodedQuery.map { "?"+$0 } ?? "")
            let method = request.httpMethod ?? "GET"
            guard ["GET","POST","PUT","PATCH","DELETE","HEAD"].contains(method),!target.contains("\r"),!target.contains("\n") else { throw RMError.invalidInput }
            var headers = request.allHTTPHeaderFields ?? [:]
            for (name,value) in headers {
                guard !name.contains(":"),!name.contains("\r"),!name.contains("\n"),!value.contains("\r"),!value.contains("\n"),!value.contains("\0") else { throw RMError.invalidInput }
            }
            let bodyBytes = request.httpBody
            let length:Int
            if let bodyBytes { length = bodyBytes.count }
            else if request.httpBodyStream != nil { guard let value = request.value(forHTTPHeaderField:"Content-Length").flatMap(Int.init),value >= 0 else { throw RMError.invalidInput }; length = value }
            else { length = 0 }
            guard length <= 50*1024*1024 else { throw RMError.tooLarge }
            for key in Array(headers.keys) where ["host","connection","accept-encoding","content-length","transfer-encoding","cookie","proxy-authorization"].contains(key.lowercased()) { headers[key] = nil }
            headers["Host"] = host; headers["Connection"] = "close"; headers["Accept-Encoding"] = "identity"
            headers["Content-Length"] = String(length)
            if headers.keys.allSatisfy({ $0.lowercased() != "user-agent" }) { headers["User-Agent"] = "RepoManager/1.0" }
            let header = "\(method) \(target) HTTP/1.1\r\n"+headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)\r\n" }.joined()+"\r\n"
            try Task.checkCancellation(); try await channel.send(Data(header.utf8))
            if let bodyBytes { for start in stride(from:0,to:bodyBytes.count,by:65536) { try Task.checkCancellation(); try await channel.send(bodyBytes.subdata(in:start..<min(start+65536,bodyBytes.count))) } }
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var bytes = [UInt8](repeating:0,count:65536); var remaining = length
                while remaining > 0 {
                    try Task.checkCancellation(); let count = stream.read(&bytes,maxLength:min(remaining,bytes.count))
                    guard count > 0 else { throw RMError.corruptRecord }; remaining -= count; try await channel.send(Data(bytes.prefix(count)))
                }
            }
            var framer = HTTPResponseFramer(limit:limit),checked = false
            while !framer.complete {
                try Task.checkCancellation(); let (bytes,eof) = try await channel.receive()
                let chunks = try framer.feed(bytes,eof:eof)
                if let head = framer.head,!checked {
                    try onResponse(HTTPResult(status:head.status,data:Data(),headers:head.headers))
                    if checkStatus { try SecureHTTPTransport.checkStatus(head.status) }; checked = true
                }
                for chunk in chunks { try Task.checkCancellation(); try emit(chunk) }
            }
            guard let head = framer.head else { throw RMError.connection }
            return HTTPResult(status:head.status,data:Data(),headers:head.headers)
        } onCancel: { channel.cancel() }
    }
}

private final class TLSChannel:@unchecked Sendable {
    private let connection:NWConnection
    private let queue = DispatchQueue(label:"com.mesutcydev.repomanager.pinned-https")
    init(ip:String,hostname:String) throws {
        let endpoint:NWEndpoint.Host
        if let address = IPv4Address(ip) { endpoint = .ipv4(address) }
        else if let address = IPv6Address(ip) { endpoint = .ipv6(address) }
        else { throw RMError.insecureURL }
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions,hostname)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions,.TLSv12)
        sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions,"http/1.1")
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions,{ _,trust,complete in
            let value = sec_trust_copy_ref(trust).takeRetainedValue()
            complete(PinnedTLSVerification.accept(value,hostname:hostname))
        },queue)
        connection = NWConnection(host:endpoint,port:443,using:NWParameters(tls:tls,tcp:NWProtocolTCP.Options()))
    }
    func connect() async throws {
        let pair = AsyncThrowingStream<Void,Error>.makeStream(bufferingPolicy:.bufferingOldest(1))
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: pair.continuation.yield(()); pair.continuation.finish()
            case .failed(let error): pair.continuation.finish(throwing:Self.safe(error))
            case .waiting: pair.continuation.finish(throwing:RMError.connection)
            case .cancelled: pair.continuation.finish(throwing:RMError.cancelled)
            default: break
            }
        }
        try Task.checkCancellation(); connection.start(queue:queue)
        for try await _ in pair.stream { return }; throw RMError.connection
    }
    func cancel() { connection.cancel() }
    func send(_ data:Data) async throws {
        try await withCheckedThrowingContinuation { (c:CheckedContinuation<Void,Error>) in
            connection.send(content:data,completion:.contentProcessed { error in if let error { c.resume(throwing:Self.safe(error)) } else { c.resume() } })
        }
    }
    func receive() async throws -> (Data,Bool) {
        try await withCheckedThrowingContinuation { c in
            connection.receive(minimumIncompleteLength:1,maximumLength:65536) { bytes,_,eof,error in
                if let error { c.resume(throwing:Self.safe(error)) } else { c.resume(returning:(bytes ?? Data(),eof)) }
            }
        }
    }
    private static func safe(_ error:NWError) -> RMError { if case .tls = error { return .insecureURL }; return .connection }
}

enum PinnedTLSVerification {
    static func accept(_ trust:SecTrust,hostname:String) -> Bool {
        guard SecTrustSetPolicies(trust,SecPolicyCreateSSL(true,hostname as CFString)) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust,false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust,nil)
    }
}
