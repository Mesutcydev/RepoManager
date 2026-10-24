import Foundation
import CryptoKit
import Security
import Testing
@testable import RepoManagerCore

private let chatGPTTestTime = Date(timeIntervalSince1970: 1_790_000_000)

private func chatGPTProfile() -> ProviderProfile {
    var profile = ProviderProfile(preset: .openAI, title: "ChatGPT")
    profile.authentication = .chatGPT; profile.consentEndpoint = profile.endpoint
    profile.models = [ModelMetadata(id: "account-model")]
    return profile
}
private func callbackURL(_ attempt: ChatGPTAuthorizationAttempt, clientID: String? = "oaiapp_fixture", state: String? = nil) -> URL {
    var components = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
    components.queryItems = [.init(name: "code", value: "synthetic-code"), .init(name: "state", value: state ?? attempt.state)]
    if let clientID { components.queryItems?.append(.init(name: "client_id", value: clientID)) }
    return components.url!
}
private func query(_ url: URL) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}
private func formFields(_ request: URLRequest) -> [String: String] {
    query(URL(string: "https://fixture.invalid/?" + String(data: request.httpBody ?? Data(), encoding: .utf8)!)!)
}

private actor ChatGPTFixture {
    let key = P256.Signing.PrivateKey()
    var nonce = "", clientID = "oaiapp_fixture", subject = "account-subject"
    var scope = ChatGPTAuth.scopes
    var exchangeFailure: String?, refreshFailure: String?
    var delayExchange = false
    var requests: [URLRequest] = []
    var inference = HTTPResult(status: 200, data: Data("event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"usage\":{\"input_tokens\":2,\"output_tokens\":1}}}\n\n".utf8))
    var modelList: JSON = .object(["models": .array([
        .object(["slug": "z-model", "display_name": "Z model", "visibility": "list"]),
        .object(["slug": "hidden-model", "display_name": "Hidden", "visibility": "hidden"]),
        .object(["slug": "a-model", "display_name": "A model", "visibility": "list"])
    ])])
    var refreshCount = 0
    func prepare(_ attempt: ChatGPTAuthorizationAttempt, clientID: String = "oaiapp_fixture", subject: String = "account-subject") {
        nonce = attempt.nonce; self.clientID = clientID; self.subject = subject
    }
    func configureScope(_ value: String) { scope = value }
    func configureExchangeFailure(_ value: String?) { exchangeFailure = value }
    func configureExchangeDelay() { delayExchange = true }
    func configureRefreshFailure(_ value: String?) { refreshFailure = value }
    func configureInference(_ value: HTTPResult) { inference = value }
    func allRequests() -> [URLRequest] { requests }
    func renewals() -> Int { refreshCount }
    func claims() -> [String: JSON] {
        ["iss": .string(ChatGPTAuth.issuer), "aud": .string(clientID), "sub": .string(subject),
         "nonce": .string(nonce), "exp": .number(chatGPTTestTime.timeIntervalSince1970 + 3600),
         "iat": .number(chatGPTTestTime.timeIntervalSince1970), "email": "same@example.test", "name": "Fixture Account"]
    }
    func sign(_ claims: [String: JSON], header: JSON = .object(["alg": "ES256", "kid": "fixture-key"])) throws -> String {
        let message = ChatGPTAuth.base64URL(header.encoded) + "." + ChatGPTAuth.base64URL(JSON.object(claims).encoded)
        return message + "." + ChatGPTAuth.base64URL(try key.signature(for: Data(message.utf8)).rawRepresentation)
    }
    func jwks() -> JSON {
        let bytes = key.publicKey.x963Representation
        return .object(["keys": .array([.object(["kty": "EC", "crv": "P-256", "alg": "ES256", "use": "sig", "kid": "fixture-key",
            "x": .string(ChatGPTAuth.base64URL(bytes.subdata(in: 1..<33))), "y": .string(ChatGPTAuth.base64URL(bytes.subdata(in: 33..<65)))])])])
    }
    func handle(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        switch request.url!.path {
        case "/api/accounts/oauth/token":
            let fields = formFields(request), refreshing = fields["grant_type"] == "refresh_token"
            if refreshing {
                refreshCount += 1; try await Task.sleep(for: .milliseconds(30))
                if let failure = refreshFailure { return response(.object(["error": .string(failure)]), failure == "temporary" ? 503 : 400) }
            } else {
                if delayExchange { try await Task.sleep(for: .milliseconds(100)) }
                if let failure = exchangeFailure { return response(.object(["error": .string(failure)]), 400) }
            }
            var tokens: [String: JSON] = ["access_token": .string(refreshing ? "synthetic-renewed-access" : "synthetic-access"),
                "refresh_token": .string(refreshing ? "synthetic-rotated-refresh" : "synthetic-refresh"), "token_type": "Bearer", "expires_in": 3600, "scope": .string(scope)]
            if !refreshing { tokens["id_token"] = .string(try sign(claims())) }
            return response(.object(tokens))
        case "/.well-known/jwks.json": return response(jwks())
        case "/.well-known/openid-configuration": return response(.object(["issuer": .string(ChatGPTAuth.issuer), "revocation_endpoint": "https://auth.openai.com/api/accounts/oauth/revoke"]))
        case "/api/accounts/oauth/revoke": return HTTPResult(status: 200, data: Data())
        case "/v1/models": return response(modelList)
        case "/v1/responses": return inference
        default: throw RMError.invalidInput
        }
    }
}

private func store(_ secrets: TestSecrets, _ fixture: ChatGPTFixture) -> ChatGPTConnectionStore {
    ChatGPTConnectionStore(secrets: secrets, transport: TestTransport(handler: { try await fixture.handle($0) }), now: { chatGPTTestTime })
}
private func connectedProfile(_ secrets: TestSecrets, expires: Date = chatGPTTestTime.addingTimeInterval(3600)) throws -> ProviderProfile {
    var profile = chatGPTProfile()
    let account = ChatGPTAccount(clientID: "oaiapp_fixture", subject: "account-subject", email: "same@example.test", name: nil)
    let record = ChatGPTCredentialRecord(clientID: account.clientID, account: account, accessToken: "synthetic-access",
        refreshToken: "synthetic-refresh", idToken: "synthetic-id", scopes: Set(ChatGPTAuth.scopes.split(separator: " ").map(String.init)), expiresAt: expires)
    try secrets.write(JSONEncoder().encode(record), account: ChatGPTConnectionStore.key(profile.id))
    profile.chatGPTAccount = account; return profile
}

private struct StreamTailFixture: HTTPTransport {
    let bytes: Data
    let reset: Bool
    var separatePackets = false
    func send(_ request: URLRequest, limit: Int) async throws -> HTTPResult { throw RMError.unsupported }
    func stream(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish(throwing: RMError.unsupported) } }
    func streamResponse(_ request: URLRequest, limit: Int) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
        AsyncThrowingStream { output in
            let task = Task {
                output.yield(.response(status: 200, headers: [:]))
                if separatePackets {
                    for frame in String(decoding:bytes,as:UTF8.self).components(separatedBy:"\n\n") where !frame.isEmpty {
                        output.yield(.data(Data((frame+"\n\n").utf8)))
                    }
                } else { output.yield(.data(bytes)) }
                do {
                    if reset { throw RMError.connection }
                    try await Task.sleep(for: .seconds(2))
                    output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }
}

private func streamFixtureFrame(_ root: JSON) throws -> Data {
    Data("data: ".utf8) + (try JSONEncoder().encode(root)) + Data("\n\n".utf8)
}

@Suite struct ChatGPTTests {
    @Test(arguments: [false, true]) func completedResponseEndsBeforeSocketTail(_ reset: Bool) async throws {
        let secrets = TestSecrets(), auth = ChatGPTFixture(), profile = try connectedProfile(secrets)
        let bytes = try streamFixtureFrame(.object(["type": "response.output_text.delta", "delta": "Completed answer"]))
            + streamFixtureFrame(.object(["type": "response.completed", "response": .object(["usage": .object(["input_tokens": 881, "output_tokens": 100])])]))
        let client = ChatGPTProviderClient(connections: store(secrets, auth), transport: StreamTailFixture(bytes: bytes, reset: reset))
        let clock = ContinuousClock(), start = clock.now
        var text = "", finish: String?, usage: Usage?
        for try await event in client.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Review")])) {
            switch event { case .text(let value): text += value; case .finish(let value): finish = value; case .usage(let value): usage = value; default: break }
        }
        #expect(text == "Completed answer" && finish == "stop")
        #expect(usage?.input == 881 && usage?.output == 100)
        #expect(start.duration(to: clock.now) < .seconds(1), "A terminal provider response must not wait for TCP shutdown")
    }

    @Test func interruptedResponseWithoutCompletionStillFails() async throws {
        let secrets = TestSecrets(), auth = ChatGPTFixture(), profile = try connectedProfile(secrets)
        let bytes = try streamFixtureFrame(.object(["type": "response.output_text.delta", "delta": "Partial answer"]))
        let client = ChatGPTProviderClient(connections: store(secrets, auth), transport: StreamTailFixture(bytes: bytes, reset: true))
        var finish = false
        await #expect(throws: RMError.connection) {
            for try await event in client.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Review")])) {
                if case .finish = event { finish = true }
            }
        }
        #expect(!finish)
    }

    @Test(arguments:[false,true]) func burstDeltasRemainLosslessForSlowConsumer(_ separatePackets:Bool) async throws {
        let secrets = TestSecrets(), auth = ChatGPTFixture(), profile = try connectedProfile(secrets)
        var bytes = Data(), expected = ""
        for index in 0..<500 {
            let delta = "\(index) 👩🏽‍💻 "
            expected += delta
            bytes += try streamFixtureFrame(.object(["type": "response.output_text.delta", "delta": .string(delta)]))
        }
        bytes += try streamFixtureFrame(.object(["type": "response.completed", "response": .object([:])]))
        let client = ChatGPTProviderClient(connections: store(secrets, auth), transport: StreamTailFixture(bytes: bytes, reset: false,separatePackets:separatePackets))
        var text = "", finish = false, paused = false
        for try await event in client.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Review")])) {
            if !paused { paused = true; try await Task.sleep(for: .milliseconds(100)) }
            switch event { case .text(let value): text += value; case .finish("stop"): finish = true; default: break }
        }
        #expect(text == expected && finish, "One received packet may contain hundreds of deltas; every byte must survive")
    }

    @Test func dynamicRegistrationAndStableHost() async throws {
        let secrets = TestSecrets(), fixture = ChatGPTFixture(), id = UUID()
        let connections = store(secrets, fixture), uri = URL(string: "http://127.0.0.1:1455/auth/callback")!
        let first = try await connections.begin(profileID: id, redirectURI: uri)
        let other = try await connections.begin(profileID: UUID(), redirectURI: uri)
        let fields = query(first.authorizationURL)
        #expect(fields["client_id"] == "dynamic_agent_client")
        #expect(fields["agent_name_hint"] == "Repo Manager")
        #expect(fields["ext_agent_host_id"] == query(other.authorizationURL)["ext_agent_host_id"])
        #expect(fields["ext_agent_host_id"]?.hasPrefix("urn:uuid:") == true)
        #expect(fields["scope"] == ChatGPTAuth.scopes)
        #expect(fields["code_challenge"] == ChatGPTAuth.base64URL(Data(SHA256.hash(data: Data(first.verifier.utf8)))))
        #expect(first.state != other.state && first.nonce != other.nonce && first.verifier != other.verifier)
        await fixture.prepare(first)
        let session = try await connections.complete(first, callbackURL: callbackURL(first))
        #expect(session.connected && session.planUsageEnabled)
        #expect(session.account?.subject == "account-subject")
        let request = try #require(await fixture.allRequests().first(where: { $0.url == ChatGPTAuth.tokenURL }))
        let exchange = formFields(request)
        #expect(exchange["client_id"] == "oaiapp_fixture")
        #expect(exchange["redirect_uri"] == uri.absoluteString)
        #expect(exchange["code_verifier"] == first.verifier && exchange["client_secret"] == nil)
        #expect(exchange["resource"] == ChatGPTAuth.resource)
        await #expect(throws: ChatGPTSignInError.expired) { try await connections.complete(first, callbackURL: callbackURL(first)) }
        let returning = try await connections.begin(profileID: id, redirectURI: URL(string: "http://127.0.0.1:54321/auth/callback")!)
        #expect(query(returning.authorizationURL)["client_id"] == "oaiapp_fixture")
        #expect(query(returning.authorizationURL)["agent_name_hint"] == nil)
        #expect(query(returning.authorizationURL)["id_token_hint"] != nil)
        #expect(try returning.callback(callbackURL(returning, clientID: nil), now: chatGPTTestTime).clientID == "oaiapp_fixture")
        #expect(throws: ChatGPTSignInError.invalidCallback) { try returning.callback(callbackURL(returning, clientID: "oaiapp_other"), now: chatGPTTestTime) }
    }

    @Test func callbackValidationAndDecline() async throws {
        let connections = store(TestSecrets(), ChatGPTFixture())
        let attempt = try await connections.begin(profileID: UUID(), redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
        #expect(throws: ChatGPTSignInError.invalidCallback) { try attempt.callback(callbackURL(attempt, state: "wrong"), now: chatGPTTestTime) }
        #expect(throws: ChatGPTSignInError.invalidCallback) { try attempt.callback(callbackURL(attempt, clientID: nil), now: chatGPTTestTime) }
        #expect(throws: ChatGPTSignInError.invalidCallback) { try attempt.callback(callbackURL(attempt, clientID: "dynamic_agent_client"), now: chatGPTTestTime) }
        #expect(throws: ChatGPTSignInError.expired) { try attempt.callback(callbackURL(attempt), now: attempt.expiresAt) }
        var duplicated = URLComponents(url: callbackURL(attempt), resolvingAgainstBaseURL: false)!
        duplicated.queryItems?.append(.init(name: "state", value: attempt.state))
        #expect(throws: ChatGPTSignInError.invalidCallback) { try attempt.callback(duplicated.url!, now: chatGPTTestTime) }
        var denied = URLComponents(url: attempt.redirectURI, resolvingAgainstBaseURL: false)!
        denied.queryItems = [.init(name: "state", value: attempt.state), .init(name: "error", value: "access_denied")]
        #expect(throws: ChatGPTSignInError.declined) { try attempt.callback(denied.url!, now: chatGPTTestTime) }
        denied.queryItems?[0].value = "wrong"
        #expect(throws: ChatGPTSignInError.invalidCallback) { try attempt.callback(denied.url!, now: chatGPTTestTime) }
        for uri in ["http://localhost:1455/auth/callback", "http://127.0.0.1:1455/callback", "https://127.0.0.1:1455/auth/callback", "http://192.168.1.1:1455/auth/callback"] {
            await #expect(throws: ChatGPTSignInError.invalidCallback) { try await connections.begin(profileID: UUID(), redirectURI: URL(string: uri)!) }
        }
    }

    @Test func signedIdentityValidation() async throws {
        let fixture = ChatGPTFixture()
        let claims = await fixture.claims(), keys = await fixture.jwks()
        let token = try await fixture.sign(claims)
        #expect(try ChatGPTIdentityVerifier.verify(token, jwks: keys, clientID: "oaiapp_fixture", nonce: "", now: chatGPTTestTime).subject == "account-subject")
        for (field, value) in [("iss", JSON.string("https://attacker.invalid")), ("aud", .string("oaiapp_other")), ("nonce", .string("wrong")),
                               ("sub", .string("")), ("exp", .number(chatGPTTestTime.timeIntervalSince1970 - 30)), ("iat", .number(chatGPTTestTime.timeIntervalSince1970 + 100))] {
            var changed = claims; changed[field] = value; let invalid = try await fixture.sign(changed)
            #expect(throws: ChatGPTSignInError.invalidIdentity) { try ChatGPTIdentityVerifier.verify(invalid, jwks: keys, clientID: "oaiapp_fixture", nonce: "", now: chatGPTTestTime) }
        }
        let wrongKey = try await fixture.sign(claims, header: .object(["alg": "ES256", "kid": "unknown"]))
        #expect(throws: ChatGPTSignInError.invalidIdentity) { try ChatGPTIdentityVerifier.verify(wrongKey, jwks: keys, clientID: "oaiapp_fixture", nonce: "", now: chatGPTTestTime) }
        let unsigned = ChatGPTAuth.base64URL(JSON.object(["alg": "none"]).encoded) + "." + ChatGPTAuth.base64URL(JSON.object(claims).encoded) + "."
        #expect(throws: ChatGPTSignInError.invalidIdentity) { try ChatGPTIdentityVerifier.verify(unsigned, jwks: keys, clientID: "oaiapp_fixture", nonce: "", now: chatGPTTestTime) }
        var altered = token.split(separator: ".").map(String.init); altered[1] = ChatGPTAuth.base64URL(JSON.object(["sub": "attacker"]).encoded)
        #expect(throws: ChatGPTSignInError.invalidIdentity) { try ChatGPTIdentityVerifier.verify(altered.joined(separator: "."), jwks: keys, clientID: "oaiapp_fixture", nonce: "", now: chatGPTTestTime) }
    }

    @Test func rsaIdentitySignature() throws {
        // Public key and expired synthetic ID token, signed offline. No private
        // key is committed and no Keychain/security daemon is needed to sign.
        let token = "eyJhbGciOiJSUzI1NiIsImtpZCI6InJzYS1maXh0dXJlIn0.eyJpc3MiOiJodHRwczovL2F1dGgub3BlbmFpLmNvbSIsImF1ZCI6Im9haWFwcF9maXh0dXJlIiwic3ViIjoicnNhLWFjY291bnQiLCJub25jZSI6Im5vbmNlIiwiaWF0IjoxNzkwMDAwMDAwLCJleHAiOjE3OTAwMDM2MDB9.r4GWM1fknhRfGt9Qqu24tan2WBR-8SKyOyCEKXyMwOX_lukF5BQ_qJANH5tYi6meU6534mHMUZ79KKTeQtWeFD8XTOV-Wjg97Q49gVwpE0raRhvMqA-Rl7AFYLu892bPoI8M4hFYSFebTt19mnDVHuDkYFvXHYN-EJQs0xm8gD__SHMNzhetSkwD75c9jW_F0WKvbIQKSXMYaTjmtXG94_wcU4bpXgf3M5TQbEuVd8QxiVJVbU4jYT54zTDoladhkIgWCdmkBVVXZmlu44td_uFvvLFJ6cdXtR00b82emk5ZNe-q3O8PYTuJe31IJIGmQ--Jn28InbPfj6w3vDyRyg"
        let keys: JSON = .object(["keys": .array([.object(["kid": "rsa-fixture", "kty": "RSA", "alg": "RS256", "e": "AQAB",
            "n": "2ddLJPJS4_Fc52Wm_-bjUFKtp8rp9mukareT5EFQVeSVbjN_jymuPAyBvdWqu0eVYeEsHattD0-U-R7QwhSF3IBLsq13EHwU_z0Bc63TUpeGg3sH-RoWdJ-yOPQLYAT_upXtERS5LzXwNd5fwTxZivppH0Iq58pmst4JhQPYYN_cKNYIkVELnGFV5gRA7jB3qZAni330Yi-mErVzOvaSEd3H2xAoI3n6__7zu5Pz4rEmdBMWliCBLiPpSILQRzsmXAox7m7wYvmuYrtEv9yoZ1_Wf8hGSNDr8XTEtLx-a7xS0Fn3SjKl_aS_fOuUict0IIpdUPB99jB2x0cnON76vQ" ])])])
        #expect(try ChatGPTIdentityVerifier.verify(token, jwks: keys, clientID: "oaiapp_fixture", nonce: "nonce", now: chatGPTTestTime).subject == "rsa-account")
        #expect(throws: ChatGPTSignInError.invalidIdentity) { try ChatGPTIdentityVerifier.verify(String(token.dropLast()) + "A", jwks: keys, clientID: "oaiapp_fixture", nonce: "nonce", now: chatGPTTestTime) }
    }

    @Test func registrationSurvivesFailedExchange() async throws {
        let fixture = ChatGPTFixture(), connections = store(TestSecrets(), fixture), id = UUID()
        await fixture.configureExchangeFailure("invalid_grant")
        let attempt = try await connections.begin(profileID: id, redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
        await #expect(throws: ChatGPTServiceError.self) { try await connections.complete(attempt, callbackURL: callbackURL(attempt)) }
        let retry = try await connections.begin(profileID: id, redirectURI: attempt.redirectURI)
        #expect(query(retry.authorizationURL)["client_id"] == "oaiapp_fixture")
        #expect(!(try await connections.session(id)).connected)
    }

    @Test func identityOnlyGrantDoesNotEnableInference() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        var profile = chatGPTProfile()
        await fixture.configureScope("openid profile email")
        let attempt = try await connections.begin(profileID: profile.id, redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
        await fixture.prepare(attempt)
        let session = try await connections.complete(attempt, callbackURL: callbackURL(attempt))
        profile.chatGPTAccount = session.account
        #expect(session.connected && !session.planUsageEnabled)
        await #expect(throws: ChatGPTSignInError.planPermissionRequired) { try await connections.accessToken(for: profile) }
        let reconsent = try await connections.begin(profileID: profile.id, redirectURI: attempt.redirectURI, requestConsent: true)
        #expect(query(reconsent.authorizationURL)["prompt"] == "consent")
        #expect(query(reconsent.authorizationURL)["scope"] == ChatGPTAuth.scopes)
    }

    @Test func registrationsWithSameEmailStaySeparate() async throws {
        let fixture = ChatGPTFixture(), connections = store(TestSecrets(), fixture), firstID = UUID(), secondID = UUID()
        var accounts: [ChatGPTAccount] = []
        for (id, client) in [(firstID, "oaiapp_first"), (secondID, "oaiapp_second")] {
            let attempt = try await connections.begin(profileID: id, redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
            await fixture.prepare(attempt, clientID: client)
            accounts.append(try #require(try await connections.complete(attempt, callbackURL: callbackURL(attempt, clientID: client)).account))
        }
        #expect(accounts[0].email == accounts[1].email && accounts[0].clientID != accounts[1].clientID)
        #expect(try await connections.session(firstID).account?.clientID == "oaiapp_first")
        #expect(try await connections.session(secondID).account?.clientID == "oaiapp_second")
        #expect(try await connections.consumePlanWelcome(firstID))
        #expect(!(try await connections.consumePlanWelcome(secondID)))
    }

    @Test func returningIdentityCannotReplaceSelectedAccount() async throws {
        let secrets = TestSecrets(), fixture = ChatGPTFixture(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets)
        let attempt = try await connections.begin(profileID: profile.id, redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
        await fixture.prepare(attempt, subject: "different-person")
        await #expect(throws: ChatGPTSignInError.invalidIdentity) { try await connections.complete(attempt, callbackURL: callbackURL(attempt, clientID: nil)) }
        #expect(try await connections.accessToken(for: profile) == "synthetic-access")
        #expect(try await connections.session(profile.id).account?.subject == "account-subject")
    }

    @Test func concurrentRefreshRotatesOnlyOnce() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets, expires: chatGPTTestTime)
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 { group.addTask { try await connections.accessToken(for: profile) } }
            var values: [String] = []; for try await value in group { values.append(value) }; return values
        }
        #expect(tokens.count == 8 && Set(tokens) == ["synthetic-renewed-access"])
        #expect(await fixture.renewals() == 1)
        let data = try #require(try secrets.read(ChatGPTConnectionStore.key(profile.id)))
        #expect(try JSONDecoder().decode(ChatGPTCredentialRecord.self, from: data).refreshToken == "synthetic-rotated-refresh")
        let request = try #require(await fixture.allRequests().first)
        #expect(formFields(request)["scope"] == nil && formFields(request)["client_id"] == "oaiapp_fixture")
    }

    @Test func temporaryRefreshFailureRetainsCredentials() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets, expires: chatGPTTestTime)
        await fixture.configureRefreshFailure("temporary")
        await #expect(throws: ChatGPTServiceError.self) { try await connections.accessToken(for: profile) }
        #expect(try await connections.session(profile.id).connected)
        await fixture.configureRefreshFailure("invalid_grant")
        await #expect(throws: ChatGPTServiceError.self) { try await connections.accessToken(for: profile) }
        #expect(!(try await connections.session(profile.id)).connected)
        #expect(try await connections.session(profile.id).account?.clientID == "oaiapp_fixture")
    }

    @Test func signOutRevokesAndKeepsRegistration() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets)
        #expect(try await connections.signOut(profile.id))
        #expect(!(try await connections.session(profile.id)).connected)
        let request = try #require(await fixture.allRequests().first(where: { $0.url?.path.hasSuffix("/revoke") == true }))
        #expect(formFields(request)["token_type_hint"] == "refresh_token")
        #expect(formFields(request)["client_id"] == "oaiapp_fixture")
        let next = try await connections.begin(profileID: profile.id, redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
        #expect(query(next.authorizationURL)["client_id"] == "oaiapp_fixture" && query(next.authorizationURL)["id_token_hint"] == nil)
    }

    @Test func accountCatalogAndWireContract() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets)
        let provider = ChatGPTProviderClient(connections: connections, transport: TestTransport(handler: { try await fixture.handle($0) }))
        let models = try await provider.catalog(profile)
        #expect(models.map(\.id) == ["z-model", "a-model"] && models.first?.displayName == "Z model")
        var request = RunRequest(conversationID: UUID(), profile: profile, model: "account-model", messages: [ChatMessage(role: .system, text: "Instructions"), ChatMessage(role: .user, text: "Hello")])
        request.tools = [.init(name: "read_file", group: "files", description: "Read a file", schema: .object(["type": "object", "properties": .object([:]), "additionalProperties": false]))]
        let body = try ProviderWire.body(request)
        #expect(body["store"].bool == false && body["stream"].bool == true && body["max_output_tokens"] == .null)
        #expect(body["input"].array?.count == 1 && body["instructions"].string == "Instructions")
        #expect(body["tools"].array?.first?["type"].string == "namespace")
        #expect(body["tools"].array?.first?["name"].string == "repo_manager")
        var events: [ChatEvent] = []; for try await event in provider.stream(request) { events.append(event) }
        #expect(events.contains { if case .text("Hello") = $0 { true } else { false } })
        #expect(events.contains { if case .finish("stop") = $0 { true } else { false } })
        var changed = profile; changed.endpoint = "https://attacker.invalid/v1"
        await #expect(throws: RMError.invalidInput) { try await connections.accessToken(for: changed) }
    }

    @Test func lateUsageFailureNeverCompletesOrExecutesTools() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets)
        let text = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}\n\ndata: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"namespace\":\"repo_manager\",\"id\":\"item\",\"call_id\":\"call\",\"name\":\"read_file\",\"arguments\":\"{}\"}}\n\ndata: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}\n\n"
        await fixture.configureInference(.init(status: 200, data: Data(text.utf8), headers: ["x-request-id": "req_fixture"]))
        let provider = ChatGPTProviderClient(connections: connections, transport: TestTransport(handler: { try await fixture.handle($0) }))
        var events: [ChatEvent] = []
        do {
            for try await event in provider.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Hello")])) { events.append(event) }
            Issue.record("A failed response was reported as successful")
        } catch let error as ChatGPTServiceError { #expect(error.requiresUsageManagement && error.requestID == "req_fixture" && error.status == 200) }
        #expect(!events.contains { if case .finish = $0 { true } else { false } })
        #expect(!events.contains { if case .tool = $0 { true } else { false } })
    }

    @Test(arguments: ["data: [DONE]\n\n", "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}\n\n", "data: {\"type\":\"response.incomplete\",\"response\":{}}\n\n"])
    func missingCompletionIsFailure(stream: String) async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets)
        await fixture.configureInference(.init(status: 200, data: Data(stream.utf8)))
        let provider = ChatGPTProviderClient(connections: connections, transport: TestTransport(handler: { try await fixture.handle($0) }))
        await #expect(throws: RMError.self) {
            for try await _ in provider.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Hello")])) {}
        }
    }

    @Test func directAdmissionPreservesSafeDiagnostics() async throws {
        let fixture = ChatGPTFixture(), secrets = TestSecrets(), connections = store(secrets, fixture)
        let profile = try connectedProfile(secrets)
        await fixture.configureInference(.init(status: 503, data: JSON.object(["detail": "untrusted diagnostic with synthetic-secret"]).encoded, headers: ["OpenAI-Request-ID": "req_503"]))
        let provider = ChatGPTProviderClient(connections: connections, transport: TestTransport(handler: { try await fixture.handle($0) }))
        do {
            for try await _ in provider.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Hello")])) {}
            Issue.record("Admission failure was ignored")
        } catch let error as ChatGPTServiceError {
            #expect(error.status == 503 && error.bodyShape == .detail && error.requestID == "req_503")
            #expect(!error.localizedDescription.contains("synthetic-secret"))
        }
        #expect(await fixture.allRequests().filter { $0.url?.path == "/v1/responses" }.count == 1)
        #expect(try await connections.session(profile.id).connected)
    }

    @Test func loopbackHTTPRejectsSmugglingAndRemoteHost() throws {
        let uri = URL(string: "http://127.0.0.1:1455/auth/callback")!
        let good = Data("GET /auth/callback?code=synthetic-code&state=synthetic-state HTTP/1.1\r\nHost: 127.0.0.1:1455\r\n\r\n".utf8)
        var parser = ChatGPTLoopbackRequestParser(), parsed: URL?
        for byte in good { parsed = try parser.feed(Data([byte]), redirectURI: uri) }
        #expect(parsed?.host == "127.0.0.1" && parsed?.path == "/auth/callback")
        for invalid in [
            "GET /auth/callback?code=x HTTP/1.1\r\nHost: attacker.invalid\r\n\r\n",
            "POST /auth/callback?code=x HTTP/1.1\r\nHost: 127.0.0.1:1455\r\n\r\n",
            "GET /auth/callback?code=x HTTP/1.1\r\nHost: 127.0.0.1:1455\r\nContent-Length: 1\r\n\r\nx",
            "GET /auth/callback?code=x HTTP/1.1\r\nHost: 127.0.0.1:1455\r\nHost: 127.0.0.1:1455\r\n\r\n",
            "GET /auth/callback?code=x HTTP/1.1\r\nHost: 127.0.0.1:1455\r\nTransfer-Encoding: chunked\r\n\r\n"
        ] {
            var rejected = ChatGPTLoopbackRequestParser()
            #expect(throws: ChatGPTSignInError.invalidCallback) { try rejected.feed(Data(invalid.utf8), redirectURI: uri) }
        }
    }

    @Test func suspendRejectsLateTokenExchange() async throws {
        let fixture = ChatGPTFixture(), connections = store(TestSecrets(), fixture), id = UUID()
        await fixture.configureExchangeDelay()
        let attempt = try await connections.begin(profileID: id, redirectURI: URL(string: "http://127.0.0.1:1455/auth/callback")!)
        await fixture.prepare(attempt)
        let pending = Task { try await connections.complete(attempt, callbackURL: callbackURL(attempt)) }
        for _ in 0..<20 {
            if await fixture.allRequests().contains(where: { $0.url == ChatGPTAuth.tokenURL }) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await connections.suspend()
        await #expect(throws: RMError.cancelled) { try await pending.value }
        #expect(!(try await connections.session(id)).connected)
    }

    @Test func safariSignInSurvivesRepeatedBackgroundAndConsumesCallbackOnce() async throws {
        let secrets = TestSecrets(), fixture = ChatGPTFixture(), connections = store(secrets,fixture)
        let uri = URL(string:"http://127.0.0.1:1455/auth/callback")!
        let retained = try await connections.begin(profileID:UUID(),redirectURI:uri)
        let unrelated = try await connections.begin(profileID:UUID(),redirectURI:uri)
        await fixture.prepare(retained)
        await connections.suspend(preservingSignIn:retained.id)
        await connections.suspend(preservingSignIn:retained.id)
        await #expect(throws:ChatGPTSignInError.expired) { try await connections.complete(unrelated,callbackURL:callbackURL(unrelated)) }
        let session = try await connections.complete(retained,callbackURL:callbackURL(retained))
        #expect(session.connected && session.planUsageEnabled)
        await #expect(throws:ChatGPTSignInError.expired) { try await connections.complete(retained,callbackURL:callbackURL(retained)) }
    }

    @Test func unownedOrCancelledSafariAttemptCannotCompleteAfterBackground() async throws {
        let connections = ChatGPTConnectionStore(secrets:TestSecrets(),now:{chatGPTTestTime})
        let uri = URL(string:"http://127.0.0.1:1455/auth/callback")!
        let unowned = try await connections.begin(profileID:UUID(),redirectURI:uri)
        await connections.suspend(preservingSignIn:UUID())
        await #expect(throws:ChatGPTSignInError.expired) { try await connections.complete(unowned,callbackURL:callbackURL(unowned)) }
        let cancelled = try await connections.begin(profileID:UUID(),redirectURI:uri)
        await connections.cancel(cancelled)
        await connections.suspend(preservingSignIn:cancelled.id)
        await #expect(throws:ChatGPTSignInError.expired) { try await connections.complete(cancelled,callbackURL:callbackURL(cancelled)) }
    }

    @Test func nativeLoopbackOnlyRedirectsAfterValidatedCallback() async throws {
        let listener = ChatGPTLoopbackListener(), connections = ChatGPTConnectionStore(secrets: TestSecrets())
        let uri = try await listener.start()
        let attempt = try await connections.begin(profileID: UUID(), redirectURI: uri)
        let returnURL = URL(string: "com.mesutcydev.repomanager.chatgpt://complete/synthetic-dismissal-marker")!
        try await listener.expect(attempt, browserReturnURL: returnURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpShouldSetCookies = false; configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration, delegate: ChatGPTNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (_, invalid) = try await session.data(from: callbackURL(attempt, state: "wrong"))
            #expect((invalid as? HTTPURLResponse)?.statusCode == 400)
            let waiting = Task { try await listener.waitForCallback() }
            let (body, valid) = try await session.data(from: callbackURL(attempt))
            let response = try #require(valid as? HTTPURLResponse)
            #expect(response.statusCode == 302 && response.value(forHTTPHeaderField: "Location") == returnURL.absoluteString)
            #expect(body.isEmpty && response.value(forHTTPHeaderField: "Cache-Control") == "no-store")
            #expect(try await waiting.value == callbackURL(attempt))
            await listener.stop()
        } catch { await listener.stop(); throw error }
    }
}

extension ChatGPTTests {
    @Test func requestFailureDisplaysOnlyBoundedDiagnostics() {
        let failure = ChatGPTServiceError(status: 400, body: .object(["error": .object(["code": "invalid_request_error", "param": "input[2].call_id", "message": "synthetic-secret"])]))
        #expect(failure.localizedDescription.contains("HTTP 400"))
        #expect(failure.localizedDescription.contains("invalid_request_error"))
        #expect(failure.localizedDescription.contains("input[2].call_id"))
        #expect(!failure.localizedDescription.contains("synthetic-secret"))
        let malformed = ChatGPTServiceError(status: 500, body: .object(["error": .object(["code": "synthetic-secret", "param": "input.synthetic-secret", "message": "synthetic-secret"])]))
        #expect(!malformed.localizedDescription.contains("synthetic-secret"))
    }

    @Test func completedOutputRejectsForeignToolNamespaces() async throws {
        let secrets = TestSecrets(), fixture = ChatGPTFixture(), profile = try connectedProfile(secrets)
        let root: JSON = .object(["type": "response.completed", "response": .object(["output": .array([
            .object(["type": "function_call", "id": "fc_foreign", "call_id": "call_foreign", "namespace": "foreign", "name": "calculator", "arguments": "{}"])
        ])])])
        var data = Data("data: ".utf8); data.append(try JSONEncoder().encode(root)); data.append(Data("\n\n".utf8))
        await fixture.configureInference(HTTPResult(status: 200, data: data))
        let provider = ChatGPTProviderClient(connections: store(secrets, fixture), transport: TestTransport(handler: { try await fixture.handle($0) }))
        var events: [ChatEvent] = []
        do {
            for try await event in provider.stream(.init(conversationID: UUID(), profile: profile, model: "account-model", messages: [.init(role: .user, text: "Calculate")])) { events.append(event) }
            Issue.record("A foreign namespace was accepted")
        } catch let error as RMError { #expect(error == .upstream) }
        #expect(!events.contains { if case .tool = $0 { true } else { false } })
    }

    @Test(arguments: [false, true], [8192, 65536])
    func repositoryToolsReplayNativeOutputAndCanAuditAgain(thinking: Bool, budget: Int) async throws {
        let services = try await FixtureServices.make()
        await services.fixture.configureTree((0..<500).map { index in
            .object(["path": .string("Sources/Feature\(index)/RepositoryAuditAndPresentationSettings.swift"),
                     "type": "blob", "mode": "100644", "sha": .string(blobSHA), "size": 8])
        })
        let secrets = TestSecrets(), auth = ChatGPTFixture(), wire = ChatGPTReplayFixture(requiresCompaction: budget == 8192)
        var profile = try connectedProfile(secrets)
        profile.models = [ModelMetadata(id: "gpt-6.1-sol")]
        let provider = ChatGPTProviderClient(connections: store(secrets, auth), transport: TestTransport(handler: { try await wire.handle($0) }))
        let runner = RunCoordinator(provider: provider, tools: services.tools, approvals: services.approvals)
        let id = UUID(), user = ChatMessage(role: .user, text: "Audit repo for cleanup and better display")
        var history = [user]
        for _ in 0..<2 {
            var response = ChatMessage(role: .assistant)
            let input = RunRequest(conversationID: id, profile: profile, model: "gpt-6.1-sol", messages: history, inputBudget: budget, thinking: thinking)
            var events: [ChatEvent] = []
            for try await event in await runner.stream(input, context: ScopedToolContext(conversationID: id, repository: services.scope, mode: .plan)) {
                events.append(event)
                if case .protocolRound(let rows) = event { ConversationContext.record(rows,in:&response) }
            }
            #expect(events.contains { if case .text("Repository audit completed.") = $0 { true } else { false } })
            #expect(events.contains { if case .finish("stop") = $0 { true } else { false } })
            if budget == 8192 { #expect(events.contains { if case .compaction(let text) = $0 { text.contains("long tool results") } else { false } }) }
            let results = events.compactMap { if case .result(let result) = $0, result.status == .success { result } else { nil } }
            #expect(results.map(\.name) == ["repository_context_map", "list_files"])
            history += ConversationContext.messages([response]); history.append(user)
        }
        #expect(await wire.count() == 4)
        #expect(await services.fixture.writes().isEmpty)
    }

    @Test func completedResponseCanCarryTheAuthoritativeToolItems() throws {
        var decoder = ProviderEventDecoder(format: .responses)
        let native = ChatGPTReplayFixture.items(turn: 0)
        let root: JSON = .object(["type": "response.completed", "response": .object(["output": .array(native)])])
        let events = try decoder.decode(SSEFrame(event: "message", data: root.encoded))
        let calls = events.compactMap { if case .tool(let call) = $0 { call } else { nil } }
        #expect(calls.map(\.name) == ["repository_context_map", "list_files"])
        let state = try #require(events.compactMap { if case .providerState(let value) = $0 { value } else { nil } }.last)
        var profile = chatGPTProfile(); profile.models = [ModelMetadata(id: "gpt-6.1-sol")]
        var answer = ChatMessage(role: .assistant, text: "Inspecting the repository."); answer.calls = calls
        answer.providerContinuation = ProviderContinuation(profileID: profile.id, modelID: "gpt-6.1-sol", endpoint: profile.endpoint, payload: state)
        let body = try ProviderWire.body(RunRequest(conversationID: UUID(), profile: profile, model: "gpt-6.1-sol", messages: [.init(role: .user, text: "Audit"), answer]))
        #expect(Array(try #require(body["input"].array).dropFirst()) == native)
    }

    @Test func oldEncryptedReasoningDoesNotReferenceAnUnstoredItem() throws {
        let profile = chatGPTProfile(), model = "account-model"
        var answer = ChatMessage(role: .assistant)
        answer.calls = [.init(id: "call_old", name: "list_files", arguments: .object([:]))]
        answer.providerContinuation = ProviderContinuation(profileID: profile.id, modelID: model, endpoint: profile.endpoint,
            payload: .object(["responses": .array([.object(["type": "reasoning", "id": "rs_unstored", "encrypted_content": "opaque-legacy", "summary": .array([])])])]))
        let input = RunRequest(conversationID: UUID(), profile: profile, model: model,
                               messages: [.init(role: .user, text: "Audit"), answer, .init(role: .tool, text: "Result", toolCallID: "call_old")])
        let reasoning = try #require(try ProviderWire.body(input)["input"].array?.first(where: { $0["type"].string == "reasoning" }))
        #expect(reasoning["id"] == .null)
        #expect(reasoning["encrypted_content"].string == "opaque-legacy")
    }

    @Test(arguments: [0, 1, 2]) func interruptedVisibleToolsDoNotReplayUnmatchedOrDuplicateCalls(completed: Int) throws {
        let profile = chatGPTProfile(), model = "account-model", native = ChatGPTReplayFixture.items(turn: 0)
        let calls = native.filter { $0["type"].string == "function_call" }.map {
            ToolCall(id: $0["call_id"].string!, name: $0["name"].string!, arguments: .object([:]))
        }
        var answer = ChatMessage(role: .assistant, text: "Inspecting the repository."); answer.calls = calls
        answer.providerContinuation = ProviderContinuation(profileID: profile.id, modelID: model, endpoint: profile.endpoint,
                                                          payload: .object(["responses_output": .array(native)]))
        answer.tools = calls.prefix(completed).map { ToolResult(id: $0.id, name: $0.name, detail: "Result", status: .success) }
        let messages = ConversationContext.messages([.init(role: .user, text: "Audit"), answer])
        let body = try ProviderWire.body(RunRequest(conversationID: UUID(), profile: profile, model: model, messages: messages))
        let items = try #require(body["input"].array)
        #expect(items.filter { $0["type"].string == "function_call" }.count == completed)
        #expect(items.filter { $0["type"].string == "function_call_output" }.count == completed)
        #expect(items.filter { $0["type"].string == "reasoning" }.count == (completed == 2 ? 2 : 0))
    }
}

/// Rejects the same malformed stateless continuation a real Responses server
/// rejects. No credentials, live inference or GitHub writes leave the fixtures.
private actor ChatGPTReplayFixture {
    private var requests = 0
    private let requiresCompaction: Bool
    init(requiresCompaction: Bool = true) { self.requiresCompaction = requiresCompaction }
    static func items(turn: Int) -> [JSON] {
        [.object(["type": "reasoning", "id": .string("rs_first_\(turn)"), "encrypted_content": "opaque-first", "summary": .array([])]),
         .object(["type": "message", "id": .string("msg_commentary_\(turn)"), "role": "assistant", "phase": "commentary", "status": "completed",
                  "content": .array([.object(["type": "output_text", "text": "Inspecting the repository.", "annotations": .array([])])])]),
         .object(["type": "function_call", "id": .string("fc_z_first_\(turn)"), "call_id": .string("call_map_\(turn)"), "name": "repository_context_map",
                  "namespace": "repo_manager", "arguments": "  {}  ", "status": "completed"]),
         .object(["type": "reasoning", "id": .string("rs_second_\(turn)"), "encrypted_content": "opaque-second", "summary": .array([])]),
         .object(["type": "function_call", "id": .string("fc_a_second_\(turn)"), "call_id": .string("call_files_\(turn)"), "name": "list_files",
                  "namespace": "repo_manager", "arguments": "{}", "status": "completed"])]
    }
    func count() -> Int { requests }
    func handle(_ request: URLRequest) throws -> HTTPResult {
        let body = try JSON.parse(request.httpBody!), turn = requests / 2, followup = requests % 2 == 1
        requests += 1
        let native = Self.items(turn: turn)
        var frames: [JSON] = []
        if followup {
            let input = body["input"].array ?? []
            let replay = input.filter { item in native.contains { $0["id"] == item["id"] && item["id"] != .null } }
            let allOutputs = input.filter { $0["type"].string == "function_call_output" }
            let currentIDs = Set(native.compactMap { $0["call_id"].string })
            let outputs = allOutputs.filter { currentIDs.contains($0["call_id"].string ?? "") }
            guard replay == native, outputs.map({ $0["call_id"].string }) == ["call_map_\(turn)", "call_files_\(turn)"],
                  input.filter({ $0["type"].string == "function_call" }).map({ $0["call_id"].string }) == allOutputs.map({ $0["call_id"].string }),
                  !requiresCompaction || outputs.contains(where: { $0["output"].string?.contains("coverage is incomplete") == true }) else {
                return HTTPResult(status: 400, data: JSON.object(["error": .object(["code": "invalid_request_error", "param": "input", "message": "Untrusted synthetic diagnostic"]) ]).encoded)
            }
            let final: JSON = .object(["type": "message", "id": .string("msg_final_\(turn)"), "role": "assistant", "phase": "final", "status": "completed",
                                      "content": .array([.object(["type": "output_text", "text": "Repository audit completed.", "annotations": .array([])])])])
            frames = [.object(["type": "response.output_text.delta", "delta": "Repository audit completed."]),
                      .object(["type": "response.output_item.done", "output_index": 0, "item": final]),
                      .object(["type": "response.completed", "response": .object(["output": .array([final])])])]
        } else {
            for (index, item) in native.enumerated() {
                frames.append(.object(["type": "response.output_item.done", "output_index": .number(Double(index)), "item": item]))
            }
            frames.append(.object(["type": "response.completed", "response": .object(["output": .array(native)])]))
        }
        let encoder = JSONEncoder(); var data = Data()
        for frame in frames {
            data.append(Data("data: ".utf8)); data.append(try encoder.encode(frame)); data.append(Data("\n\n".utf8))
        }
        return HTTPResult(status: 200, data: data)
    }
}

private final class ChatGPTNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
