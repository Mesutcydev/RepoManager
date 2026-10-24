import Foundation
import Testing
import Security
import CryptoKit
@testable import RepoManagerCore

@Suite struct NetworkingAcceptance {
    @Test func unreachablePrimaryAddressUsesOtherValidatedFamily() async throws {
        let recorder = ConnectionAttempts()
        let ipv6 = "2606:4700:4700::1111",ipv4 = "8.8.8.8"
        let connected = try await ValidatedEndpoints.connect([ipv6,"2606:4700:4700::1001",ipv4]) { address in
            await recorder.add(address)
            if address.contains(":") { throw RMError.connection }
            return address
        }
        #expect(connected == ipv4)
        #expect(await recorder.values == [ipv6,ipv4])
    }
    @Test func endpointSelectionRejectsUnsafeDNSAndCertificateFailure() async throws {
        let recorder = ConnectionAttempts()
        await #expect(throws:RMError.insecureURL) {
            _ = try await ValidatedEndpoints.connect(["8.8.8.8","127.0.0.1"]) { address in await recorder.add(address); return address }
        }
        #expect(await recorder.values.isEmpty)
        await #expect(throws:RMError.insecureURL) {
            _ = try await ValidatedEndpoints.connect(["8.8.8.8","1.1.1.1"]) { address -> String in await recorder.add(address); throw RMError.insecureURL }
        }
        #expect(await recorder.values == ["8.8.8.8"], "A certificate failure must not become an alternate connection attempt")
    }
    @Test func fullStreamCanBeCancelledWithoutDroppingQueuedContent() async throws {
        let pair = AsyncThrowingStream<String,Error>.makeStream(bufferingPolicy:.bufferingOldest(1))
        try await StreamDelivery.send("first",to:pair.continuation)
        let waiting = Task { try await StreamDelivery.send("second",to:pair.continuation) }
        try await Task.sleep(for:.milliseconds(30)); waiting.cancel()
        await #expect(throws:CancellationError.self) { try await waiting.value }
        pair.continuation.finish()
        var received:[String] = []; for try await value in pair.stream { received.append(value) }
        #expect(received == ["first"])
    }
    @Test(arguments:[1,2,7,4096]) func splitHeadersAndChunkedUTF8(_ size:Int) throws {
        let text = "repository 👩🏽‍💻 İstanbul",body = Data(text.utf8)
        let wire = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/event-stream\r\nSet-Cookie: discarded\r\n\r\n\(String(body.count,radix:16));ok=1\r\n".utf8)+body+Data("\r\n0\r\nX-Usage: bounded\r\n\r\n".utf8)
        var parser = HTTPResponseFramer(limit:1024),clear = Data()
        for start in stride(from:0,to:wire.count,by:size) { for bytes in try parser.feed(wire.subdata(in:start..<min(wire.count,start+size))) { clear.append(bytes) } }
        #expect(parser.complete); #expect(clear == body); #expect(parser.head?.headers["set-cookie"] == nil)
    }
    @Test func boundedBodiesAndAmbiguousFramingFail() throws {
        for wire in [
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\nok",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nextra",
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nokBAD0\r\n\r\n"
        ] { var parser = HTTPResponseFramer(limit:20); #expect(throws:RMError.self) { try parser.feed(Data(wire.utf8),eof:true) } }
        var parser = HTTPResponseFramer(limit:1)
        #expect(throws:RMError.tooLarge) { try parser.feed(Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok".utf8)) }
        var truncated = HTTPResponseFramer(limit:4)
        #expect(throws:RMError.connection) { try truncated.feed(Data("HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nx".utf8),eof:true) }
        // Int.max chunk size after a prior chunk must throw, not trap on total+size.
        var overflow = HTTPResponseFramer(limit:8*1024*1024)
        #expect(throws:RMError.invalidInput) { try overflow.feed(Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nA\r\n7fffffffffffffff\r\n".utf8)) }
    }
    @Test func informationalResponseAndCloseDelimitedBody() throws {
        var parser = HTTPResponseFramer(limit:100)
        let data = Data("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nConnection: close\r\n\r\ncontent".utf8)
        #expect(try parser.feed(data,eof:true).reduce(Data(),+) == Data("content".utf8)); #expect(parser.complete)
    }
    @Test(arguments:["127.0.0.1","10.1.1.1","192.168.1.1","169.254.169.254","100.64.1.1","0.0.0.0","224.1.1.1","::1","::ffff:127.0.0.1","64:ff9b::7f00:1","2002:7f00:1::","2001:db8::1","2001::1","fe80::1","fd00::1","ff02::1"]) func specialUseAddressesDenied(_ address:String) { #expect(!URLPolicy.isPublicAddress(address)) }
    @Test func publicAddressesAndCredentialURLs() throws {
        #expect(URLPolicy.isPublicAddress("8.8.8.8")); #expect(URLPolicy.isPublicAddress("2606:4700:4700::1111"))
        #expect(!URLPolicy.isPublicAddress("not.an.ip"))
        for raw in ["https://example.com/?api_key=secret","https://name:password@example.com","http://example.com","https://127.1","https://example.com:8080"] {
            #expect(throws:RMError.insecureURL) { try URLPolicy.validate(URL(string:raw)!) }
        }
    }
    @Test(.enabled(if:ProcessInfo.processInfo.environment["RM_VERIFY_PUBLIC_TLS"] == "1")) func publicTLSTrustProbe() async throws {
        // Explicit opt-in; default CI uses fixtures and never performs network requests.
        let response = try await SecureHTTPTransport().send(URLRequest(url:URL(string:"https://api.github.com")!),limit:256*1024)
        #expect(response.status == 200); #expect(response.json["current_user_url"].string == "https://api.github.com/user")
        await #expect(throws:RMError.self) { try await SecureHTTPTransport().send(URLRequest(url:URL(string:"https://wrong.host.badssl.com")!),limit:1024) }
    }
    @Test func nativeTLSRejectsWrongHostnameExpiredAndChangedCertificate() throws {
        func certificate() throws -> SecCertificate {
            let key = P256.Signing.PrivateKey()
            let body = try TLSIdentity.certificateBody(publicKey:Array(key.publicKey.x963Representation),host:"localhost")
            let signature = try key.signature(for:Data(body)).derRepresentation
            let encoded = Data(DER.sequence(body+DER.sequence(DER.oid([0x2a,0x86,0x48,0xce,0x3d,0x04,0x03,0x02]))+DER.bitString(Array(signature))))
            return try #require(SecCertificateCreateWithData(nil,encoded as CFData))
        }
        let cert = try certificate(),changed = try certificate()
        func trust(anchor:SecCertificate,date:Date = Date()) throws -> SecTrust {
            var result:SecTrust?; #expect(SecTrustCreateWithCertificates(cert,SecPolicyCreateSSL(true,nil),&result) == errSecSuccess)
            let value = try #require(result); SecTrustSetAnchorCertificates(value,[anchor] as CFArray); SecTrustSetAnchorCertificatesOnly(value,true); SecTrustSetVerifyDate(value,date as CFDate); return value
        }
        #expect(PinnedTLSVerification.accept(try trust(anchor:cert),hostname:"localhost"))
        #expect(PinnedTLSVerification.accept(try trust(anchor:cert),hostname:"127.0.0.1"))
        #expect(!PinnedTLSVerification.accept(try trust(anchor:cert),hostname:"github.com"))
        #expect(!PinnedTLSVerification.accept(try trust(anchor:cert,date:Date().addingTimeInterval(60*86400)),hostname:"localhost"))
        #expect(!PinnedTLSVerification.accept(try trust(anchor:changed),hostname:"localhost"))
    }
}

private actor ConnectionAttempts {
    private(set) var values:[String] = []
    func add(_ value:String) { values.append(value) }
}
