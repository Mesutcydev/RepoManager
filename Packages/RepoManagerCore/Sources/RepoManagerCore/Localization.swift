import Foundation

/// Presentation-only lookup for catalog and schema metadata whose identifiers
/// must remain stable for tool execution, persistence, and external clients.
public enum RMLocalization {
    public static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    public static func fieldName(_ key: String) -> String {
        text(key.replacingOccurrences(of: "_", with: " ").capitalized)
    }
}

extension ToolDefinition {
    public var displayName: String { RMLocalization.fieldName(name) }
    public var localizedGroup: String { RMLocalization.text(group) }
    public var localizedDescription: String { RMLocalization.text(description) }
}

extension RunMode {
    public var title: String {
        switch self {
        case .plan: String(localized: "Plan", bundle: .module)
        case .act: String(localized: "Act", bundle: .module)
        }
    }
}

extension VoicePhase {
    public var title: String {
        switch self {
        case .idle: String(localized: "Idle", bundle: .module)
        case .listening: String(localized: "Listening", bundle: .module)
        case .transcribing: String(localized: "Transcribing", bundle: .module)
        case .responding: String(localized: "Responding", bundle: .module)
        case .speaking: String(localized: "Speaking", bundle: .module)
        case .paused: String(localized: "Paused", bundle: .module)
        case .approval: String(localized: "Awaiting approval", bundle: .module)
        }
    }
}
