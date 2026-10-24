// Adapted from OnDeviceMax; see Docs/PROVENANCE.json and LICENSE.
import SwiftUI
import UIKit

/// Shared production and preview composer. Files and submission acceptance remain host-owned.
public struct RMComposer: View {
    @Binding private var text: String
    private var focus: FocusState<Bool>.Binding
    private let attachments: [RMAttachment]
    private let isResponding: Bool
    private let canSend: Bool
    private let canStop: Bool
    private let canAdd: Bool
    private let canRemove: Bool
    private let microphone: AnyView?
    private let notice: AnyView?
    private let modelControl: AnyView?
    private let onAdd: () -> Void
    private let onRemove: (String) -> Void
    private let onSend: (String, [String]) -> Void
    private let onStop: () -> Void
    private let onVoice: (() -> Void)?
    private let thinking: Bool?
    private let onThinking: ((Bool) -> Void)?
    private let reasoningControl: AnyView?
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    @State private var writingHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var glyphSize = RMLayout.standardIcon
    private let writingHorizontalInset = RMLayout.textAdditionalHorizontalInset

    public init(text: Binding<String>, focus: FocusState<Bool>.Binding,
                attachments: [RMAttachment], isResponding: Bool,
                canSend: Bool, canStop: Bool, canAdd: Bool, canRemove: Bool,
                microphone: AnyView? = nil, notice: AnyView? = nil, modelControl: AnyView? = nil,
                onVoice: (() -> Void)? = nil,
                thinking: Bool? = nil, onThinking: ((Bool) -> Void)? = nil,
                reasoningControl: AnyView? = nil,
                onAdd: @escaping () -> Void, onRemove: @escaping (String) -> Void,
                onSend: @escaping (String, [String]) -> Void, onStop: @escaping () -> Void) {
        self._text = text
        self.focus = focus
        self.attachments = attachments
        self.isResponding = isResponding
        self.canSend = canSend
        self.canStop = canStop
        self.canAdd = canAdd
        self.canRemove = canRemove
        self.microphone = microphone
        self.notice = notice
        self.modelControl = modelControl
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onSend = onSend
        self.onStop = onStop
        self.onVoice = onVoice
        self.thinking = thinking
        self.onThinking = onThinking
        self.reasoningControl = reasoningControl
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.elementGap) {
            if let notice {
                notice
            }
            VStack(alignment: .leading, spacing: 0) {
                if !attachments.isEmpty {
                    attachmentStrip
                        .padding(.horizontal, writingHorizontalInset)
                        .padding(.bottom, RMLayout.composerAttachmentGap)
                }
                // One mounted field owns focus and selection in both layouts.
                // Replacing an HStack field with a VStack field loses first responder.
                ZStack(alignment: .topLeading) {
                    writingField
                        .padding(.leading, usesExpandedLayout ? writingHorizontalInset : RMLayout.minimumHit)
                        .padding(.trailing, usesExpandedLayout ? writingHorizontalInset : RMLayout.minimumHit * (microphone == nil ? 1 : 2) + RMLayout.composerMicPrimaryGap)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { writingHeight = $0 }
                        .padding(.vertical, usesExpandedLayout ? 0 : RMLayout.rowGap)
                    footer
                        .padding(.top, usesExpandedLayout ? writingHeight + RMLayout.composerFooterGap : 0)
                }
            }
            .padding(.horizontal, RMLayout.composerSideInset)
            .padding(.top, usesExpandedLayout ? RMLayout.composerTopInset : 0)
            .padding(.bottom, usesExpandedLayout ? RMLayout.composerBottomInset : 0)
            .frame(maxWidth: .infinity, minHeight: usesExpandedLayout ? RMLayout.composerMinimumHeight : 56)
            // Any tap on the card that no control claims focuses the text.
            .contentShape(composerShape)
            .onTapGesture { focus.wrappedValue = true }
            .glassEffect(.regular, in: composerShape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.composer.panel")
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: attachments.isEmpty)
            .animation(reduceMotion ? nil : .easeOut(duration:0.18),value:focus.wrappedValue)
        }
        .padding(.horizontal, RMLayout.pageInset)
        .padding(.top, RMLayout.elementGap)
        .padding(.bottom, RMLayout.composerInputStackGap)
    }

    private var composerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: RMLayout.composerCorner, style: .continuous)
    }

    private var prompt: Text {
        Text("Message", bundle: .module).foregroundStyle(RMPalette.secondary)
    }

    private var usesExpandedLayout: Bool {
        focus.wrappedValue || dynamicType.isAccessibilitySize || !attachments.isEmpty || text.contains("\n")
    }

    private var writingField: some View {
        TextField(text: $text, prompt: prompt, axis: .vertical) { Text("Message", bundle:.module) }
            .font(.body)
            .foregroundStyle(RMPalette.text)
            .tint(RMPalette.text)
            .lineLimit(1...6)
            .autocorrectionDisabled()
            .submitLabel(.return)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .focused(focus)
            .accessibilityLabel(Text("Message", bundle: .module))
            .accessibilityIdentifier("chat.composer.text")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: RMLayout.composerFooterGap) {
            if dynamicType.isAccessibilitySize {
                HStack(spacing: RMLayout.elementGap) { expandedModelControls }
            }
            HStack(spacing: 0) {
                addButton
                if usesExpandedLayout && !dynamicType.isAccessibilitySize {
                    expandedModelControls
                }
                Spacer(minLength: RMLayout.elementGap)
                actionControls
            }
            .frame(minHeight: RMLayout.minimumHit)
        }
    }

    @ViewBuilder private var expandedModelControls: some View {
        if let modelControl { modelControl }
        if let reasoningControl { reasoningControl } else if let thinking, let onThinking {
            thinkingButton(isOn: thinking, onToggle: onThinking)
        }
    }

    private var actionControls: some View {
        HStack(spacing: 0) {
            if microphone != nil {
                dictationControl
                primaryAction
                    .padding(.leading, RMLayout.composerMicPrimaryGap)
            } else {
                primaryAction
            }
        }
    }

    /// A naked utility icon. The host view supplies the glyph and behaviour;
    /// no chrome is added here so it cannot compete with the primary action.
    @ViewBuilder private var dictationControl: some View {
        if let microphone {
            microphone
        }
    }

    private var addButton: some View {
        Button {
            RMComposerHaptics.impact(.light)
            onAdd()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: min(glyphSize, RMLayout.composerGlyphMaximum), weight: .medium))
                .foregroundStyle(RMPalette.secondary)
                .frame(width: RMLayout.minimumHit, height: RMLayout.minimumHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(RMPressButtonStyle())
        .disabled(!canAdd)
        .accessibilityLabel(Text("Message tools and attachments", bundle: .module))
        .accessibilityIdentifier("chat.composer.add")
    }

    /// Same naked-glyph treatment as the add control; the filled glyph in ink
    /// marks the on state. Only shown for models whose reasoning can switch.
    private func thinkingButton(isOn: Bool, onToggle: @escaping (Bool) -> Void) -> some View {
        Button {
            RMComposerHaptics.impact(.light)
            onToggle(!isOn)
        } label: {
            Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: min(glyphSize, RMLayout.composerGlyphMaximum), weight: .medium))
                .foregroundStyle(isOn ? RMPalette.text : RMPalette.secondary)
                .frame(width: RMLayout.minimumHit, height: RMLayout.minimumHit)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(RMPressButtonStyle())
        .disabled(isResponding)
        .accessibilityLabel(Text("Thinking", bundle: .module))
        .accessibilityValue(isOn ? String(localized:"On",bundle:.module) : String(localized:"Off",bundle:.module))
        .accessibilityHint(Text("Reason step by step before answering", bundle: .module))
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("chat.composer.thinking")
    }

    private var offersVoice: Bool {
        !isResponding && attachments.isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && onVoice != nil
    }

    /// One anchored control, three semantic states: voice, send, stop.
    private var primaryAction: some View {
        RMComposerPrimaryAction(
            symbol: isResponding ? "stop.fill" : (offersVoice ? "waveform" : "arrow.up"),
            label: isResponding ? String(localized:"Stop response",bundle:.module) : (offersVoice ? String(localized:"Voice conversation",bundle:.module) : String(localized:"Send message",bundle:.module)),
            identifier: isResponding ? "chat.composer.stop" : (offersVoice ? "chat.composer.voice" : "chat.composer.send"),
            isEnabled: isResponding ? canStop : (offersVoice || canSend),
            hapticStyle: isResponding ? .medium : .light
        ) {
            if isResponding { onStop() }
            else if offersVoice { onVoice?() }
            else { onSend(text, attachments.map(\.id)) }
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RMLayout.elementGap) {
                ForEach(attachments) { attachment in
                    RMComposerAttachment(attachment: attachment, canRemove: canRemove, onRemove: onRemove)
                }
            }
        }
        .scrollClipDisabled()
        .frame(height: ordinaryAttachmentRow ? RMLayout.minimumHit : nil)
        .accessibilityLabel(Text("Draft attachments", bundle: .module))
    }

    /// File tokens share a 44-point row. Image previews keep their own height.
    private var ordinaryAttachmentRow: Bool {
        !dynamicType.isAccessibilitySize
    }
}

/// The composer's single emphatic control. Its geometry never changes; only the
/// glyph and meaning move between voice, send and stop, so the trailing corner
/// stays anchored across states. Stop uses a high-contrast semantic ink fill.
private struct RMComposerPrimaryAction: View {
    let symbol: String
    let label: String
    let identifier: String
    let isEnabled: Bool
    let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle
    let action: () -> Void
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var glyphSize = 16

    var body: some View {
        Button {
            RMComposerHaptics.impact(hapticStyle)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: min(glyphSize, RMLayout.composerSendDiameter / 2), weight: .semibold))
                .foregroundStyle(symbol == "stop.fill" ? RMPalette.background : RMPalette.onSend)
                .frame(width: RMLayout.composerSendDiameter, height: RMLayout.composerSendDiameter)
                .glassEffect(.regular.tint(symbol == "stop.fill" ? RMPalette.text : RMPalette.send).interactive(), in: Circle())
                .frame(width: RMLayout.minimumHit, height: RMLayout.minimumHit)
                .contentShape(Rectangle())
                .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
        }
        .buttonStyle(RMComposerPrimaryActionStyle())
        .disabled(!isEnabled)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: symbol)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

private struct RMComposerPrimaryActionStyle: ButtonStyle {
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Restrained haptics for composer commitments only — never for text changes.
@MainActor private enum RMComposerHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

/// Decode a bounded local thumbnail only when its bytes change, not on each keystroke.
private struct RMComposerAttachment: View {
    let attachment: RMAttachment
    let canRemove: Bool
    let onRemove: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text").foregroundStyle(RMPalette.secondary)
            Text(attachment.name).font(.footnote).lineLimit(1).truncationMode(.middle)
            removeButton(image: false)
        }
        .padding(.leading, 12)
        .frame(minHeight: RMLayout.minimumHit)
        .background(RMPalette.input, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(Text("Attachment: \(attachment.name)", bundle: .module))
    }

    private func removeButton(image: Bool) -> some View {
        Button { onRemove(attachment.id) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(image ? Color.white : RMPalette.secondary)
                .frame(width: 24, height: 24)
                .background(image ? Color.black.opacity(0.55) : .clear, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!canRemove)
        .accessibilityLabel(Text("Remove \(attachment.name)", bundle: .module))
    }
}

/// Right-align natural content while enforcing the documented 82% width cap.
public struct RMUserBubbleLayout: Layout {
    public var displayScale: CGFloat
    public init(displayScale: CGFloat) { self.displayScale = displayScale }
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = proposal.width ?? content.sizeThatFits(.unspecified).width
        let cap = RMLayout.maxUserBubbleWidth(contentWidth: width, displayScale: displayScale)
        let measured = content.sizeThatFits(ProposedViewSize(width: cap, height: nil))
        return CGSize(width: width, height: measured.height)
    }
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let cap = RMLayout.maxUserBubbleWidth(contentWidth: bounds.width, displayScale: displayScale)
        let measured = content.sizeThatFits(ProposedViewSize(width: cap, height: nil))
        content.place(at: CGPoint(x: bounds.maxX, y: bounds.minY), anchor: .topTrailing,
                      proposal: ProposedViewSize(width: min(cap, measured.width), height: measured.height))
    }
}
