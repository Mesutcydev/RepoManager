import Foundation

/// Public registration metadata. Tokens and App private keys never belong here.
public struct GitHubAppConfiguration: Equatable, Sendable {
    public let clientID: String
    public let appSlug: String

    public init(clientID: String?, appSlug: String?) throws {
        guard let clientID, let appSlug,
              Self.validClientID(clientID),
              !["fixture", "placeholder", "example", "dummy"].contains(where: { clientID.lowercased().contains($0) }),
              (1...100).contains(appSlug.utf8.count),
              appSlug.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
              appSlug.first != "-", appSlug.last != "-" else { throw GitHubPairingError.configurationUnavailable }
        self.clientID = clientID
        self.appSlug = appSlug
    }

    public var installationURL: URL {
        URL(string: "https://github.com/apps/\(appSlug)/installations/new")!
    }

    static func validClientID(_ value: String) -> Bool {
        value.hasPrefix("Iv") && (8...100).contains(value.utf8.count) &&
        value.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 46 }
    }
}

public enum GitHubPairingError: String, Error, LocalizedError, Sendable {
    case configurationUnavailable, deviceFlowDisabled, denied, expired, invalidResponse, rejected, browserUnavailable

    public var errorDescription: String? {
        switch self {
        case .configurationUnavailable: "GitHub sign-in is unavailable in this build. Update Repo Manager or use a fine-grained token."
        case .deviceFlowDisabled: "GitHub sign-in is temporarily unavailable. Use a fine-grained token or try again after the app is updated."
        case .denied: "GitHub sign-in was declined. You can try again when you're ready."
        case .expired: "Your GitHub sign-in code expired. Start again to get a new code."
        case .invalidResponse: "GitHub returned an invalid sign-in response. Please try again."
        case .rejected: "GitHub could not complete sign-in. Please try again."
        case .browserUnavailable: "The browser could not open. Try Open Safari again, or open github.com/login/device and enter your code."
        }
    }

    static func fromOAuth(_ value: String) -> Self {
        switch value {
        case "access_denied": .denied
        case "expired_token", "bad_verification_code": .expired
        case "device_flow_disabled": .deviceFlowDisabled
        case "incorrect_client_credentials", "unsupported_grant_type": .configurationUnavailable
        default: .rejected
        }
    }
}

/// An in-memory continuation for an explicitly initiated device sign-in.
/// It is not Codable: device codes never enter the vault, backups or history.
/// Suspending invalidates in-flight callbacks while preserving the original deadline.
public struct GitHubDeviceFlowState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case idle, requesting, waiting, suspended, connected }
    public private(set) var phase: Phase = .idle
    public private(set) var authorization: DeviceAuthorization?
    public private(set) var ticket = UUID()
    public init() {}

    @discardableResult public mutating func begin() -> UUID {
        ticket = UUID(); authorization = nil; phase = .requesting
        return ticket
    }
    @discardableResult public mutating func receive(_ authorization: DeviceAuthorization, ticket: UUID) -> Bool {
        guard self.ticket == ticket, phase == .requesting else { return false }
        self.authorization = authorization; phase = .waiting
        return true
    }
    public mutating func suspend() {
        ticket = UUID()
        phase = authorization == nil ? .idle : .suspended
    }
    public mutating func resume(at date: Date = .now) throws -> (UUID, DeviceAuthorization)? {
        guard phase == .suspended, let authorization else { return nil }
        guard authorization.expires > date else { cancel(); throw GitHubPairingError.expired }
        ticket = UUID(); phase = .waiting
        return (ticket, authorization)
    }
    public mutating func updateInterval(_ interval: Int, ticket: UUID) {
        guard self.ticket == ticket, phase == .waiting, (1...1800).contains(interval) else { return }
        authorization?.interval = interval
    }
    @discardableResult public mutating func complete(ticket: UUID) -> Bool {
        guard self.ticket == ticket, phase == .waiting || phase == .requesting else { return false }
        authorization = nil; phase = .connected
        return true
    }
    public mutating func cancel() { ticket = UUID(); authorization = nil; phase = .idle }
}
