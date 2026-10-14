import Foundation

/// Safe diagnostic fields. Upstream messages, tokens and raw response bodies are
/// deliberately excluded from display, logging and conversation history.
public struct ChatGPTServiceError: Error, LocalizedError, Equatable, Sendable {
    public enum BodyShape: String, Sendable { case structured, detail, other }
    public let status: Int
    public let code: String?
    public let parameter: String?
    public let requestID: String?
    public let bodyShape: BodyShape
    public var requiresUsageManagement: Bool { code == "subscription_sharing_usage_limit_exceeded" }
    var unusableRefreshToken: Bool {
        ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(code ?? "")
    }
    public var errorDescription: String? {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return "ChatGPT usage limit reached. Open Manage usage to review your plan and this app's limit."
        case "subscription_sharing_user_not_eligible": return "ChatGPT plan usage is unavailable for this account or workspace. Choose another provider or check eligibility in ChatGPT."
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": return "ChatGPT plan usage is temporarily unavailable. Your connection is retained; try again later."
        case "subscription_sharing_unsupported_capability", "subscription_sharing_route_not_supported": return "This request uses a capability unavailable with your ChatGPT plan. Change the request before trying again."
        case "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context": return "ChatGPT did not authorize this operation. Review this app's access in ChatGPT settings."
        case "invalid_client": return "ChatGPT rejected the app registration. Reconnect after the registration is corrected."
        default:
            if unusableRefreshToken { return ChatGPTSignInError.signedOut.localizedDescription }
            switch status {
            case 401: return "ChatGPT could not authorize this request. Check the selected account and its plan permission."
            case 403: return "ChatGPT restricted this request for the selected account, workspace, or region."
            case 429: return "ChatGPT rate limit reached. Wait before trying again."
            case 503: return "ChatGPT is temporarily unavailable. Your connection is retained; try again later."
            default: return "ChatGPT could not complete this request. Your draft and connection are retained."
            }
        }
    }
    init(status: Int, body: JSON, requestID: String? = nil) {
        self.status = status
        let error = body["error"]
        code = Self.identifier(error["code"].string ?? error.string ?? body["code"].string)
        parameter = Self.identifier(error["param"].string)
        self.requestID = Self.identifier(requestID)
        bodyShape = error != .null ? .structured : body["detail"] != .null ? .detail : .other
    }
    private static func identifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 256,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || "-_./[]".utf8.contains($0) }) else { return nil }
        return value
    }
}

/// One protected record per provider/registration, and one host ID per install.
/// Refreshes are shared within this actor, preventing rotating-token races.
public actor ChatGPTConnectionStore {
    private let secrets: any SecretStore
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var attempts: [UUID: ChatGPTAuthorizationAttempt] = [:]
    private var epochs: [UUID: UInt64] = [:]
    private var refreshes: [UUID: (UUID, Task<ChatGPTCredentialRecord, Error>)] = [:]
    private var cachedJWKS: (JSON, Date)?
    private var revocationURL: URL?
    public init(secrets: any SecretStore = KeychainStore(), transport: any HTTPTransport = SecureHTTPTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.secrets = secrets; self.transport = transport; self.now = now
    }
    static func key(_ id: UUID) -> String { "chatgpt:profile:\(id.uuidString)" }
    private func read(_ id: UUID) throws -> ChatGPTCredentialRecord? {
        guard let data = try secrets.read(Self.key(id)) else { return nil }
        guard data.count <= 256 * 1024 else { throw RMError.corruptRecord }
        do { return try JSONDecoder().decode(ChatGPTCredentialRecord.self, from: data) }
        catch { throw RMError.corruptRecord }
    }
    private func write(_ record: ChatGPTCredentialRecord, _ id: UUID) throws {
        try secrets.write(JSONEncoder().encode(record), account: Self.key(id))
    }
    private func hostID() throws -> String {
        if let saved = try secrets.read("chatgpt:host-id"), let value = String(data: saved, encoding: .utf8),
           value.hasPrefix("urn:uuid:"), UUID(uuidString: String(value.dropFirst(9))) != nil { return value }
        if try secrets.read("chatgpt:host-id") != nil { throw RMError.corruptRecord }
        let value = "urn:uuid:" + UUID().uuidString.lowercased()
        try secrets.write(Data(value.utf8), account: "chatgpt:host-id"); return value
    }
    public func session(_ id: UUID) throws -> ChatGPTSession {
        try read(id)?.session ?? ChatGPTSession(account: nil, connected: false, planUsageEnabled: false)
    }
    public func begin(profileID: UUID, redirectURI: URL, requestConsent: Bool = false) async throws -> ChatGPTAuthorizationAttempt {
        if let (_, task) = refreshes[profileID] { _ = try await task.value }
        try Task.checkCancellation()
        let attempt = try ChatGPTAuthorizationAttempt(profileID: profileID, redirectURI: redirectURI, hostID: hostID(),
            registration: read(profileID), requestConsent: requestConsent, now: now())
        epochs[profileID, default: 0] &+= 1
        attempts[profileID] = attempt; return attempt
    }
    public func cancel(_ attempt: ChatGPTAuthorizationAttempt) {
        guard attempts[attempt.profileID]?.id == attempt.id else { return }
        attempts[attempt.profileID] = nil; epochs[attempt.profileID, default: 0] &+= 1
    }
    public func complete(_ attempt: ChatGPTAuthorizationAttempt, callbackURL: URL) async throws -> ChatGPTSession {
        let id = attempt.profileID
        guard attempts[id]?.id == attempt.id else { throw ChatGPTSignInError.expired }
        // Consume even a malformed or denied callback; retries need fresh state.
        attempts[id] = nil
        let epoch = epochs[id, default: 0]
        let callback = try attempt.callback(callbackURL, now: now())
        var record = try read(id) ?? ChatGPTCredentialRecord(clientID: callback.clientID)
        guard record.clientID == callback.clientID else { throw ChatGPTSignInError.invalidCallback }
        // Keep the issued registration if exchange fails, without replacing any
        // existing validated account or active credentials.
        try write(record, id)
        let tokens = try await tokenRequest([
            "grant_type": "authorization_code", "client_id": callback.clientID, "code": callback.code,
            "code_verifier": attempt.verifier, "redirect_uri": attempt.redirectURI.absoluteString, "resource": ChatGPTAuth.resource
        ])
        guard let idToken = tokens["id_token"].string else { throw ChatGPTSignInError.invalidIdentity }
        let account = try await identity(idToken, clientID: callback.clientID, nonce: attempt.nonce)
        guard attempt.expectedSubject == nil || attempt.expectedSubject == account.subject else { throw ChatGPTSignInError.invalidIdentity }
        record.account = account; record.idToken = idToken
        record = try applying(tokens, to: record, refreshing: false)
        try Task.checkCancellation(); guard epochs[id, default: 0] == epoch else { throw RMError.cancelled }
        try write(record, id); return record.session
    }
    public func accessToken(for profile: ProviderProfile) async throws -> String {
        try ChatGPTAuth.validateProfile(profile)
        guard var record = try read(profile.id), let account = record.account, let selected = profile.chatGPTAccount,
              account.clientID == selected.clientID, account.subject == selected.subject, record.session.connected else { throw ChatGPTSignInError.signedOut }
        guard record.session.planUsageEnabled else { throw ChatGPTSignInError.planPermissionRequired }
        if (record.expiresAt ?? .distantPast) <= now().addingTimeInterval(60) {
            if let earliest = record.earliestRefreshAt, now() < earliest, (record.expiresAt ?? .distantPast) > now() {
                // Respect a server-supplied earliest refresh time.
            } else { record = try await refresh(profile.id, record: record) }
        }
        guard record.session.planUsageEnabled, let token = record.accessToken, (record.expiresAt ?? .distantPast) > now() else { throw ChatGPTSignInError.signedOut }
        return token
    }
    private func refresh(_ id: UUID, record: ChatGPTCredentialRecord) async throws -> ChatGPTCredentialRecord {
        if let (_, task) = refreshes[id] { return try await task.value }
        guard let refreshToken = record.refreshToken else { throw ChatGPTSignInError.signedOut }
        let ticket = UUID(), epoch = epochs[id, default: 0]
        let task = Task {
            do {
                let tokens = try await self.tokenRequest(["grant_type": "refresh_token", "client_id": record.clientID,
                    "refresh_token": refreshToken, "resource": ChatGPTAuth.resource])
                var updated = try self.applying(tokens, to: record, refreshing: true)
                if let idToken = tokens["id_token"].string {
                    let account = try await self.identity(idToken, clientID: record.clientID, nonce: nil)
                    guard account.subject == record.account?.subject else { throw ChatGPTSignInError.invalidIdentity }
                    updated.account = account; updated.idToken = idToken
                }
                try Task.checkCancellation(); guard self.epochs[id, default: 0] == epoch else { throw RMError.cancelled }
                try self.write(updated, id); return updated
            } catch {
                if let failure = error as? ChatGPTServiceError, failure.unusableRefreshToken, self.epochs[id, default: 0] == epoch {
                    var cleared = record; cleared.clearTokens(); try self.write(cleared, id)
                }
                throw error
            }
        }
        refreshes[id] = (ticket, task)
        defer { if refreshes[id]?.0 == ticket { refreshes[id] = nil } }
        return try await task.value
    }
    private func tokenRequest(_ fields: [String: String]) async throws -> JSON {
        var request = URLRequest(url: ChatGPTAuth.tokenURL)
        request.httpMethod = "POST"; request.httpBody = ChatGPTAuth.form(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let result = try await transport.send(request, limit: 256 * 1024)
        guard result.status == 200 else { throw ChatGPTServiceError(status: result.status, body: result.json, requestID: Self.requestID(result.headers)) }
        guard result.json.object != nil else { throw RMError.upstream }
        return result.json
    }
    private func applying(_ tokens: JSON, to original: ChatGPTCredentialRecord, refreshing: Bool) throws -> ChatGPTCredentialRecord {
        var record = original
        guard let scope = tokens["scope"].string, scope.utf8.count <= 4096 else { throw RMError.upstream }
        record.scopes = Set(scope.split(whereSeparator: \.isWhitespace).map(String.init))
        func credential(_ value: JSON) throws -> String? {
            if value == .null { return nil }
            guard let token = value.string, !token.isEmpty, token.utf8.count <= 65536,
                  !token.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }) else { throw RMError.upstream }
            return token
        }
        record.accessToken = try credential(tokens["access_token"])
        record.refreshToken = try credential(tokens["refresh_token"])
        if record.accessToken != nil {
            guard tokens["token_type"].string?.lowercased() == "bearer", let lifetime = tokens["expires_in"].int,
                  lifetime > 0, lifetime <= 86400 else { throw RMError.upstream }
            record.expiresAt = now().addingTimeInterval(Double(lifetime))
            record.earliestRefreshAt = tokens["earliest_refresh_at"].int.map { Date(timeIntervalSince1970: Double($0)) }
        } else { record.expiresAt = nil; record.earliestRefreshAt = nil }
        if refreshing { guard record.accessToken != nil, record.refreshToken != nil else { throw RMError.upstream } }
        if record.scopes.contains(ChatGPTAuth.directScope) {
            guard record.accessToken != nil, record.scopes.contains("resource.invoke") else { throw RMError.upstream }
        }
        return record
    }
    private func identity(_ token: String, clientID: String, nonce: String?) async throws -> ChatGPTAccount {
        let header = try ChatGPTIdentityVerifier.header(token)
        let known = cachedJWKS.map { $0.1 > now() && $0.0["keys"].array?.contains(where: { $0["kid"] == header["kid"] }) == true } ?? false
        if !known {
            let result = try await transport.send(URLRequest(url: ChatGPTAuth.jwksURL), limit: 256 * 1024)
            try SecureHTTPTransport.checkStatus(result.status)
            guard result.json["keys"].array != nil else { throw ChatGPTSignInError.invalidIdentity }
            cachedJWKS = (result.json, now().addingTimeInterval(3600))
        }
        guard let (keys, _) = cachedJWKS else { throw ChatGPTSignInError.invalidIdentity }
        return try ChatGPTIdentityVerifier.verify(token, jwks: keys, clientID: clientID, nonce: nonce, now: now())
    }
    /// Clears tokens but keeps the issued client/account mapping and host ID.
    /// False means local sign-out finished without confirmed remote revocation.
    public func signOut(_ id: UUID) async throws -> Bool {
        epochs[id, default: 0] &+= 1; attempts[id] = nil
        let epoch = epochs[id, default: 0]
        if let (_, task) = refreshes.removeValue(forKey: id) { task.cancel(); _ = try? await task.value }
        guard var record = try read(id) else { return true }
        var confirmed = record.refreshToken == nil
        if let token = record.refreshToken {
            for attempt in 0..<2 {
                do {
                    if revocationURL == nil {
                        let result = try await transport.send(URLRequest(url: ChatGPTAuth.discoveryURL), limit: 65536)
                        try SecureHTTPTransport.checkStatus(result.status)
                        guard result.json["issuer"].string == ChatGPTAuth.issuer,
                              let value = result.json["revocation_endpoint"].string, let url = URL(string: value),
                              url.host == "auth.openai.com", url.query == nil else { throw RMError.insecureURL }
                        try URLPolicy.validate(url); revocationURL = url
                    }
                    guard let url = revocationURL else { throw RMError.upstream }
                    var request = URLRequest(url: url); request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                    request.httpBody = ChatGPTAuth.form(["token": token, "token_type_hint": "refresh_token", "client_id": record.clientID])
                    let result = try await transport.send(request, limit: 65536)
                    if result.status == 200 { confirmed = true; break }
                    if result.status < 500 { break }
                } catch { if Task.isCancelled { break } }
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }
        guard epochs[id, default: 0] == epoch else { throw RMError.cancelled }
        record.clearTokens(); try write(record, id); return confirmed
    }
    public func forget(_ id: UUID) async throws -> Bool {
        let confirmed = try await signOut(id); try secrets.delete(Self.key(id)); return confirmed
    }
    public func suspend(preservingSignIn attemptID: UUID? = nil) {
        for id in Set(epochs.keys).union(attempts.keys).union(refreshes.keys) { epochs[id, default: 0] &+= 1 }
        // Preserve only the explicitly owned, unconsumed Safari attempt. All
        // in-flight token exchanges/refreshes still lose their write lease.
        attempts = attempts.filter { $0.value.id == attemptID && now() < $0.value.expiresAt }
        for (_, task) in refreshes.values { task.cancel() }; refreshes.removeAll()
        cachedJWKS = nil
    }
    public func consumePlanWelcome(_ id: UUID) throws -> Bool {
        guard try session(id).planUsageEnabled, try secrets.read("chatgpt:plan-welcome") == nil else { return false }
        try secrets.write(Data([1]), account: "chatgpt:plan-welcome"); return true
    }
    static func requestID(_ headers: [String: String]) -> String? {
        let normalized = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        return normalized["openai-request-id"] ?? normalized["x-request-id"]
    }
}
