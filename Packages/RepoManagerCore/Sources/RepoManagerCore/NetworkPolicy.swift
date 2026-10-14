import Foundation
import Network
import Security

public enum InputValidation {
    public static func component(_ value: String) throws -> String {
        guard !value.isEmpty, value.count <= 200, value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }),
              value != ".", value != ".." else { throw RMError.invalidInput }
        return value
    }
    public static func entitySegment(_ value:String) throws -> String {
        guard !value.isEmpty,value.utf8.count <= 200,value != ".",value != "..",!value.contains("%"),
              !value.unicodeScalars.contains(where:{ $0.value < 32 || $0.value == 127 }) else { throw RMError.invalidInput }
        return value
    }
    public static func path(_ value: String, allowRoot: Bool = false) throws -> String {
        if allowRoot && value.isEmpty { return value }
        guard !value.isEmpty, value.utf8.count <= 1024, !value.hasPrefix("/"), !value.hasSuffix("/"), !value.contains("\\"),
              !value.contains("%"), !value.contains("\0"), !value.contains(":"), !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw RMError.invalidInput }
        return value
    }
    public static func ref(_ value: String) throws -> String {
        guard !value.isEmpty, value.count <= 200, !value.hasPrefix("-"), !value.hasPrefix("/"), !value.hasSuffix("/"),
              !value.hasSuffix("."), !value.contains(".."), !value.contains("@{"), !value.contains("//"), value != "@",
              !value.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 || "~^:?*[\\%".unicodeScalars.contains($0) }),
              value.split(separator: "/").allSatisfy({ !$0.hasPrefix(".") && !$0.hasSuffix(".lock") }) else { throw RMError.invalidInput }
        return value
    }
    public static func sha(_ value: String) throws -> String {
        guard [40,64].contains(value.count), value.allSatisfy({ $0.isHexDigit }) else { throw RMError.invalidInput }; return value
    }
    public static func model(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 250, !value.contains(".."), !value.contains("%"),
              value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-._/:".unicodeScalars.contains($0) }) else { throw RMError.invalidInput }; return value
    }
}
public enum URLPolicy {
    public static func validate(_ url: URL, allowLAN: Bool = false) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil, !host.hasSuffix("."),
              !url.absoluteString.contains("\n"), !url.absoluteString.contains("\r"), url.port == nil || url.port == 443 else { throw RMError.insecureURL }
        if !allowLAN {
            guard !privateHost(host) else { throw RMError.insecureURL }
        }
        let fields = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
        let credentialNames = Set(["key","api_key","apikey","token","access_token","auth","authorization","password","secret","signature","credential"])
        guard !fields.contains(where:{ credentialNames.contains($0.name.lowercased()) || RepositorySecretScanner.scan($0.value ?? "").findings.count > 0 }) else { throw RMError.insecureURL }
    }
    public static func privateHost(_ host: String) -> Bool {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "localhost" || h.hasSuffix(".local") || !h.contains(".") && !h.contains(":") { return true }
        if h.contains(":") { return true } // Literal IPv6, including mapped IPv4, is denied for outgoing content tools.
        let parts = h.split(separator: ".").compactMap { UInt8($0) }
        if parts.count == 4 {
            let a = parts[0], b = parts[1], c = parts[2]
            return a == 0 || a == 10 || a == 127 || a == 169 && b == 254 || a == 172 && (16...31).contains(b)
                || a == 192 && (b == 168 || b == 0 && (c == 0 || c == 2) || b == 88 && c == 99) || a == 100 && (64...127).contains(b) || a >= 224
                || a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) || a == 203 && b == 0 && c == 113
        }
        // Noncanonical integer, octal, hex, and shortened numeric IP spellings.
        return h.hasPrefix("0x") || h.allSatisfy({ $0.isNumber || $0 == "." })
    }
    public static func resolvePublic(_ url: URL) async throws -> [String] {
        try validate(url)
        guard let host = url.host else { throw RMError.insecureURL }
        let addresses: [String] = try await Task.detached(priority: .utility) {
            var hint = addrinfo(); hint.ai_socktype = SOCK_STREAM; hint.ai_family = AF_UNSPEC
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, "443", &hint, &result) == 0, let first = result else { throw RMError.connection }
            defer { freeaddrinfo(first) }
            var values: [String] = []; var ptr: UnsafeMutablePointer<addrinfo>? = first
            while let p = ptr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(p.pointee.ai_addr, p.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    values.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern:$0) }, as:UTF8.self))
                }
                ptr = p.pointee.ai_next
            }
            return values
        }.value
        try Task.checkCancellation()
        guard !addresses.isEmpty, addresses.allSatisfy(isPublicAddress) else { throw RMError.insecureURL }
        return addresses
    }
    public static func isPublicAddress(_ address:String) -> Bool {
        if !address.contains(":") { var ip = in_addr(); return inet_pton(AF_INET,address,&ip) == 1 && !privateHost(address) }
        var ip = in6_addr()
        guard inet_pton(AF_INET6,address,&ip) == 1 else { return false }
        let bytes = withUnsafeBytes(of:ip) { Array($0) }
        // Accept global unicast only. Reject ULA/link-local/multicast/mapped/NAT64 and transition ranges.
        guard bytes[0]&0xe0 == 0x20 else { return false }
        if bytes[0] == 0x3f,bytes[1] == 0xff,bytes[2]&0xf0 == 0 { return false } // documentation 3fff::/20
        if bytes[0] == 0x20,bytes[1] == 0x02 { return false } // 6to4 embeds a potentially private IPv4 destination.
        if bytes[0] == 0x20,bytes[1] == 0x01 {
            if bytes[2] <= 1 { return false } // IANA special-use block, including Teredo and ORCHID.
            if bytes[2] == 0x0d,bytes[3] == 0xb8 { return false } // documentation
        }
        return true
    }
    public static func append(_ base: URL, segments: [String], query: [String: String] = [:]) throws -> URL {
        try validate(base)
        guard var c = URLComponents(url:base,resolvingAgainstBaseURL:false) else { throw RMError.invalidInput }
        var path = c.percentEncodedPath
        for segment in segments {
            let encoded = try encodedSegment(segment)
            if !path.hasSuffix("/") { path += "/" }; path += encoded
        }
        c.percentEncodedPath = path
        if !query.isEmpty { c.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let result = c.url else { throw RMError.invalidInput }; return result
    }
    public static func encodedSegment(_ value:String) throws -> String {
        guard !value.isEmpty,value != ".",value != "..",!value.unicodeScalars.contains(where:{ $0.value < 32 || $0.value == 127 }),
              let encoded = value.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed.subtracting(CharacterSet(charactersIn:"/%?#"))) else { throw RMError.invalidInput }
        return encoded
    }
}
public struct HTTPResult: Sendable {
    public var status: Int; public var data: Data; public var headers: [String: String]
    public init(status: Int, data: Data, headers: [String: String] = [:]) { self.status = status; self.data = data; self.headers = headers }
    public var json: JSON { (try? JSON.parse(data)) ?? .null }
}
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest, limit: Int) async throws -> HTTPResult
    func stream(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<Data, Error>
    func streamResponse(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<HTTPStreamEvent, Error>
}
public enum HTTPStreamEvent: Sendable { case response(status: Int, headers: [String: String]), data(Data) }
public extension HTTPTransport {
    /// Fixture/adapter fallback. The production transport overrides this to
    /// stream without buffering a successful response.
    func streamResponse(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    let result = try await send(request, limit: limit)
                    try Task.checkCancellation()
                    output.yield(.response(status: result.status, headers: result.headers)); output.yield(.data(result.data)); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
}
/// Each request connects to one already-validated IP with the original hostname used for TLS verification.
/// There are no redirects, cookies, caches, system proxy routing, alternate endpoints, or automatic retries.
public final class SecureHTTPTransport: HTTPTransport, Sendable {
    public init() {}
    public func send(_ request:URLRequest,limit:Int = 4*1024*1024) async throws -> HTTPResult {
        let buffer = HTTPAccumulator(limit:limit)
        var result = try await PinnedHTTPS.exchange(request,limit:limit,checkStatus:false) { try buffer.append($0) }
        result.data = buffer.data; return result
    }
    public func stream(_ request:URLRequest,limit:Int = 8*1024*1024) -> AsyncThrowingStream<Data,Error> {
        AsyncThrowingStream(bufferingPolicy:.bufferingOldest(16)) { output in
            let task = Task {
                do {
                    _ = try await PinnedHTTPS.exchange(request,limit:limit,checkStatus:true) { chunk in
                        switch output.yield(chunk) {
                        case .dropped: throw RMError.tooLarge
                        case .terminated: throw RMError.cancelled
                        case .enqueued: break
                        @unknown default: throw RMError.cancelled
                        }
                    }
                    output.finish()
                } catch is CancellationError { output.finish(throwing:RMError.cancelled) }
                catch { output.finish(throwing:error as? RMError ?? .connection) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
    public func streamResponse(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(16)) { output in
            let task = Task {
                @Sendable func emit(_ event: HTTPStreamEvent) throws {
                    switch output.yield(event) {
                    case .dropped: throw RMError.tooLarge
                    case .terminated: throw RMError.cancelled
                    case .enqueued: break
                    @unknown default: throw RMError.cancelled
                    }
                }
                do {
                    _ = try await PinnedHTTPS.exchange(request, limit: limit, checkStatus: false,
                        onResponse: { try emit(.response(status: $0.status, headers: $0.headers)) },
                        emit: { try emit(.data($0)) })
                    output.finish()
                } catch is CancellationError { output.finish(throwing: RMError.cancelled) }
                catch { output.finish(throwing: error as? RMError ?? .connection) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
    public static func checkStatus(_ status: Int) throws {
        switch status { case 200..<300: return; case 401: throw RMError.authentication; case 403: throw RMError.forbidden
        case 404: throw RMError.unavailable; case 409,422: throw RMError.conflict; case 429: throw RMError.rateLimited
        case 300..<400: throw RMError.insecureURL; default: throw RMError.upstream }
    }
}
