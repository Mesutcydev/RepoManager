import Foundation

public enum ProviderDisclosure {
    public static func modelNotice(profile:ProviderProfile,model:String) -> String? {
        guard [.openCodeGo,.openCodeZen].contains(profile.preset) else { return nil }
        let id = model.lowercased()
        if id.contains("contributor") {
            return String(localized:"This contributor model may use prompts and responses to train future models. Repository contents and your conversation would be included. Review OpenCode's current privacy terms before continuing.",bundle:.module)
        }
        if id.contains("free") || id.contains("big-pickle") || id.contains("big_pickle") {
            return String(localized:"Free and trial models can have different retention and training terms. Some OpenCode models use prompts and responses for model improvement; NVIDIA trial endpoints advise against confidential content. Review the current terms for this exact model before sending repository contents.",bundle:.module)
        }
        return nil
    }
    public static func validate(profile:ProviderProfile,model:String) throws {
        guard profile.consentEndpoint == profile.endpoint else { throw RMError.consentRequired }
        if modelNotice(profile:profile,model:model) != nil,profile.privacyConsentedModels?.contains(model) != true { throw RMError.consentRequired }
    }
}
