import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct ReasoningControl: View {
    @Bindable var model: AppModel
    let conversation: Conversation
    private var preference:ReasoningPreference { conversation.reasoningPreference ?? (conversation.thinking ? .high : .automatic) }
    private var capabilities:ReasoningCapabilities {
        guard let profile = model.data.providers.first(where:{ $0.id == conversation.providerID }) else { return .init(kind:.providerDefault,levels:[]) }
        return ReasoningPolicy.capabilities(profile:profile,model:conversation.modelID)
    }
    var body: some View {
        Menu {
            ForEach(capabilities.choices,id:\.self) { value in
                Button { model.stop(conversation.id); model.editConversation { $0.reasoningPreference = value } } label: {
                    if preference == value { Label(value.title,systemImage:"checkmark") } else { Text(value.title) }
                }
            }
            Divider()
            Text(capabilities.kind == .promptGuidance ? "Answer guidance; native reasoning controls are unavailable." : "Auto adapts within this model's capabilities and your output cap.")
        } label: {
            // Ink like every composer glyph; the filled bulb carries the state.
            Image(systemName:preference == .off ? "lightbulb" : "lightbulb.fill")
                .font(.system(size:RMLayout.standardIcon,weight:.medium)).foregroundStyle(RMPalette.text)
                .frame(width:RMLayout.minimumHit,height:RMLayout.minimumHit).contentShape(Rectangle())
        }.buttonStyle(RMPressButtonStyle()).disabled(conversation.providerID == nil)
            .accessibilityLabel("Reasoning").accessibilityValue(preference.title).accessibilityIdentifier("chat.composer.thinking")
    }
}
