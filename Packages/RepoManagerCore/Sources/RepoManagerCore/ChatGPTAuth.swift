import Foundation
import CryptoKit
import Security

/// Public protocol constants from OpenAI's Sign in with ChatGPT documentation.
/// This integration does not use Codex client IDs or ChatGPT backend endpoints.
public enum ChatGPTAuth {
    public static let issuer = "https://auth.openai.com"
    public static let authorizeURL = URL(string: issuer + "/api/accounts/authorize")!
    public static let tokenURL = URL(string: issuer + "/api/accounts/oauth/token")!
    public static let discoveryURL = URL(string: issuer + "/.well-known/openid-configuration")!
    public static let jwksURL = URL(string: issuer + "/.well-known/jwks.json")!
    public static let resource = "https://api.openai.com/v1"
    public static let usageURL = URL(string: "https://chatgpt.com/settings/usage")!
    public static let directScope = "chatgpt.tokens.use.direct"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let dynamicClientID = "dynamic_agent_client"

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    static func decodeBase64URL(_ value: String) throws -> Data {
        guard !value.isEmpty, value.utf8.count <= 65536,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw ChatGPTSignInError.invalidIdentity }
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            + String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: padded), base64URL(data) == value else { throw ChatGPTSignInError.invalidIdentity }
        return data
    }
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "="
                + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
    }
    public static func validateProfile(_ profile: ProviderProfile) throws {
        guard profile.usesChatGPT, profile.preset == .openAI, profile.endpoint == resource,
              profile.format == .responses, !profile.textToolBridge else { throw RMError.invalidInput }
    }
    static func validateClientID(_ value: String) throws {
        guard value != dynamicClientID, value.hasPrefix("oaiapp_"), value.utf8.count <= 256,
              value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { throw ChatGPTSignInError.invalidCallback }
    }
    static func validateRedirect(_ url: URL) throws {
        guard url.scheme == "http", url.host == "127.0.0.1", let port = url.port, (1024...65535).contains(port),
              url.path == "/auth/callback", url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw ChatGPTSignInError.invalidCallback }
    }
}

public enum ChatGPTSignInError: String, Error, LocalizedError, Sendable {
    case invalidCallback, invalidIdentity, expired, declined, signedOut, planPermissionRequired, browserUnavailable
    public var errorDescription: String? {
        switch self {
        case .invalidCallback: "The ChatGPT sign-in response could not be verified. Start sign-in again."
        case .invalidIdentity: "The ChatGPT account could not be verified. Start sign-in again."
        case .expired: "ChatGPT sign-in expired. Start sign-in again."
        case .declined: "ChatGPT sign-in was cancelled. You can continue with another provider or sign in again."
        case .signedOut: "Sign in to this ChatGPT account again to continue."
        case .planPermissionRequired: "Enable ChatGPT plan usage for this account or choose an API-key provider."
        case .browserUnavailable: "The browser could not open ChatGPT sign-in. Try again when the app is active."
        }
    }
}

/// Display metadata only. Credentials never enter AppData or history exports.
public struct ChatGPTAccount: Codable, Equatable, Sendable {
    public let clientID: String
    public let subject: String
    public let email: String?
    public let name: String?
    public var label: String { email ?? name ?? "ChatGPT account" }
    public var registrationLabel: String { String(clientID.suffix(8)) }
}

public struct ChatGPTSession: Equatable, Sendable {
    public let account: ChatGPTAccount?
    public let connected: Bool
    public let planUsageEnabled: Bool
}

public struct ChatGPTAuthorizationAttempt: Sendable {
    public let id: UUID
    public let profileID: UUID
    public let redirectURI: URL
    public let state: String
    public let expiresAt: Date
    public let authorizationURL: URL
    let nonce: String
    let verifier: String
    let clientID: String?
    let expectedSubject: String?

    init(profileID: UUID, redirectURI: URL, hostID: String, registration: ChatGPTCredentialRecord?, requestConsent: Bool, now: Date) throws {
        try ChatGPTAuth.validateRedirect(redirectURI)
        id = UUID(); self.profileID = profileID; self.redirectURI = redirectURI
        state = ChatGPTAuth.base64URL(try RecordCrypto.random(32))
        nonce = ChatGPTAuth.base64URL(try RecordCrypto.random(32))
        verifier = ChatGPTAuth.base64URL(try RecordCrypto.random(64))
        expiresAt = now.addingTimeInterval(600)
        clientID = registration?.clientID; expectedSubject = registration?.account?.subject
        if let clientID { try ChatGPTAuth.validateClientID(clientID) }
        var fields: [String: String] = [
            "client_id": clientID ?? ChatGPTAuth.dynamicClientID,
            "ext_agent_host_id": hostID, "response_type": "code", "redirect_uri": redirectURI.absoluteString,
            "scope": ChatGPTAuth.scopes, "resource": ChatGPTAuth.resource, "state": state, "nonce": nonce,
            "code_challenge_method": "S256", "code_challenge": ChatGPTAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        ]
        if clientID == nil { fields["agent_name_hint"] = "Repo Manager" }
        else {
            fields["id_token_hint"] = registration?.idToken
            fields["login_hint"] = registration?.account?.email
        }
        if requestConsent { fields["prompt"] = "consent" }
        var components = URLComponents(url: ChatGPTAuth.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw RMError.invalidInput }
        authorizationURL = url
    }

    /// A callback is accepted once by the connection store, after this validation.
    public func callback(_ url: URL, now: Date = Date()) throws -> ChatGPTAuthorizationCallback {
        guard now < expiresAt else { throw ChatGPTSignInError.expired }
        guard url.scheme == redirectURI.scheme, url.host == redirectURI.host, url.port == redirectURI.port,
              url.path == redirectURI.path, url.user == nil, url.password == nil, url.fragment == nil,
              url.absoluteString.utf8.count <= 8192,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              Set(items.map(\.name)).count == items.count else { throw ChatGPTSignInError.invalidCallback }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let returnedState = fields["state"], RecordCrypto.constantTimeEqual(Data(returnedState.utf8), Data(state.utf8)) else { throw ChatGPTSignInError.invalidCallback }
        if let error = fields["error"] {
            if error == "access_denied" { throw ChatGPTSignInError.declined }
            throw ChatGPTSignInError.invalidCallback
        }
        guard let code = fields["code"], !code.isEmpty, code.utf8.count <= 4096,
              !code.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw ChatGPTSignInError.invalidCallback }
        let issuedID: String
        if let clientID {
            guard fields["client_id"] == nil || fields["client_id"] == clientID else { throw ChatGPTSignInError.invalidCallback }
            issuedID = clientID
        } else {
            guard let value = fields["client_id"] else { throw ChatGPTSignInError.invalidCallback }
            try ChatGPTAuth.validateClientID(value); issuedID = value
        }
        return ChatGPTAuthorizationCallback(code: code, clientID: issuedID)
    }
}

public struct ChatGPTAuthorizationCallback: Equatable, Sendable {
    let code: String
    public let clientID: String
}

struct ChatGPTCredentialRecord: Codable, Sendable {
    var clientID: String
    var account: ChatGPTAccount?
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var scopes: Set<String> = []
    var expiresAt: Date?
    var earliestRefreshAt: Date?
    var session: ChatGPTSession {
        .init(account: account, connected: account != nil && idToken != nil,
              planUsageEnabled: account != nil && accessToken != nil && scopes.contains(ChatGPTAuth.directScope) && scopes.contains("resource.invoke"))
    }
    mutating func clearTokens() {
        accessToken = nil; refreshToken = nil; idToken = nil; scopes = []; expiresAt = nil; earliestRefreshAt = nil
    }
}

/// Apple Security verifies RS256; CryptoKit verifies ES256. No unverified claim
/// is used for account linking, and token-supplied key URLs are never followed.
enum ChatGPTIdentityVerifier {
    static func header(_ token: String) throws -> JSON {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.utf8.count <= 65536 else { throw ChatGPTSignInError.invalidIdentity }
        return try JSON.parse(ChatGPTAuth.decodeBase64URL(String(parts[0])))
    }
    static func verify(_ token: String, jwks: JSON, clientID: String, nonce: String?, now: Date) throws -> ChatGPTAccount {
        do {
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            let header = try header(token)
            guard let algorithm = header["alg"].string, ["RS256", "ES256"].contains(algorithm),
                  header["crit"] == .null, header["jku"] == .null, header["jwk"] == .null,
                  let keyID = header["kid"].string, !keyID.isEmpty, keyID.utf8.count <= 256,
                  let keys = jwks["keys"].array, keys.count <= 100 else { throw ChatGPTSignInError.invalidIdentity }
            let matching = keys.filter { $0["kid"].string == keyID }
            guard matching.count == 1, let key = matching.first,
                  key["use"] == .null || key["use"].string == "sig",
                  key["alg"] == .null || key["alg"].string == algorithm,
                  key["key_ops"] == .null || key["key_ops"].array?.contains("verify") == true else { throw ChatGPTSignInError.invalidIdentity }
            let signature = try ChatGPTAuth.decodeBase64URL(String(parts[2]))
            let signed = Data((parts[0] + "." + parts[1]).utf8)
            if algorithm == "RS256" {
                guard key["kty"].string == "RSA", let n = key["n"].string, let e = key["e"].string else { throw ChatGPTSignInError.invalidIdentity }
                let modulus = try ChatGPTAuth.decodeBase64URL(n), exponent = try ChatGPTAuth.decodeBase64URL(e)
                guard (256...1024).contains(modulus.count), !exponent.isEmpty, exponent.count <= 8 else { throw ChatGPTSignInError.invalidIdentity }
                func integer(_ data: Data) -> [UInt8] {
                    var bytes = Array(data.drop(while: { $0 == 0 })); if bytes.first.map({ $0 & 0x80 != 0 }) == true { bytes.insert(0, at: 0) }
                    return DER.integer(bytes)
                }
                let encoded = Data(DER.sequence(integer(modulus) + integer(exponent)))
                let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
                guard let publicKey = SecKeyCreateWithData(encoded as CFData, attributes as CFDictionary, nil),
                      SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil) else { throw ChatGPTSignInError.invalidIdentity }
            } else {
                guard key["kty"].string == "EC", key["crv"].string == "P-256", let x = key["x"].string, let y = key["y"].string else { throw ChatGPTSignInError.invalidIdentity }
                let xBytes = try ChatGPTAuth.decodeBase64URL(x), yBytes = try ChatGPTAuth.decodeBase64URL(y)
                guard xBytes.count == 32, yBytes.count == 32, signature.count == 64 else { throw ChatGPTSignInError.invalidIdentity }
                let publicKey = try P256.Signing.PublicKey(x963Representation: Data([4]) + xBytes + yBytes)
                guard publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: signed) else { throw ChatGPTSignInError.invalidIdentity }
            }
            let claims = try JSON.parse(ChatGPTAuth.decodeBase64URL(String(parts[1])))
            let audience = claims["aud"].string.map { [$0] } ?? claims["aud"].array?.compactMap(\.string) ?? []
            guard claims["iss"].string == ChatGPTAuth.issuer, audience.contains(clientID),
                  audience.count <= 1 || claims["azp"].string == clientID,
                  let expiry = claims["exp"].int, let issued = claims["iat"].int,
                  Double(expiry) > now.timeIntervalSince1970 - 5, Double(issued) <= now.timeIntervalSince1970 + 5, expiry > issued,
                  claims["nbf"] == .null || Double(claims["nbf"].int ?? Int.max) <= now.timeIntervalSince1970 + 5,
                  let subject = claims["sub"].string, !subject.isEmpty, subject.utf8.count <= 300 else { throw ChatGPTSignInError.invalidIdentity }
            if let nonce {
                guard let returned = claims["nonce"].string, RecordCrypto.constantTimeEqual(Data(returned.utf8), Data(nonce.utf8)) else { throw ChatGPTSignInError.invalidIdentity }
            }
            func display(_ value: JSON) -> String? {
                guard let text = value.string, !text.isEmpty, text.utf8.count <= 320,
                      !text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return nil }
                return text
            }
            return ChatGPTAccount(clientID: clientID, subject: subject, email: display(claims["email"]), name: display(claims["name"]))
        } catch { throw ChatGPTSignInError.invalidIdentity }
    }
}
