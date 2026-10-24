import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct SessionModelChangeRow: View {
    let change: SessionModelChange
    var body: some View {
        HStack(spacing: RMLayout.elementGap) {
            Rectangle().fill(RMPalette.line).frame(height: 0.5)
            Text("Switched to \(change.label)").font(RMType.meta).foregroundStyle(RMPalette.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(RMPalette.line).frame(height: 0.5)
        }.accessibilityElement(children: .combine)
    }
}

struct ComposerModelButton: View {
    @Bindable var model: AppModel
    let chat: Conversation
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let label = model.data.providers.first(where: { $0.id == chat.providerID })?.models.first(where: { $0.id == chat.modelID })?.displayName ?? chat.modelID
        Button(action: action) {
            HStack(spacing: RMLayout.unit) {
                Text(label.isEmpty ? String(localized: "Choose model") : label).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.caption2)
            }.font(RMType.label).foregroundStyle(RMPalette.text).frame(minHeight: RMLayout.minimumHit)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 140)
        }.buttonStyle(.plain).accessibilityLabel(String(localized: "Model \(label)"))
            .accessibilityIdentifier("chat.modelPicker")
    }
}
