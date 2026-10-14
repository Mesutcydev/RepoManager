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
                if let modelControl {
                    HStack(spacing: RMLayout.elementGap) {
                        modelControl
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, writingHorizontalInset)
                    .padding(.bottom, RMLayout.elementGap)
                }
                if !attachments.isEmpty {
                    attachmentStrip
                        .padding(.horizontal, writingHorizontalInset)
                        .padding(.bottom, RMLayout.composerAttachmentGap)
                }
                if modelControl != nil && !dynamicType.isAccessibilitySize {
                    HStack(alignment: .bottom, spacing: RMLayout.unit) {
                        addButton
                        if let reasoningControl { reasoningControl } else if let thinking, let onThinking {
                            thinkingButton(isOn: thinking, onToggle: onThinking)
                        }
                        writingField.padding(.vertical, RMLayout.elementGap)
                        actionControls
                    }
                    .frame(minHeight: RMLayout.minimumHit)
                } else {
                    writingField
                        .padding(.horizontal, writingHorizontalInset)
                        .padding(.bottom, RMLayout.composerFooterGap)
                    footer
                }
            }
            .padding(.horizontal, RMLayout.composerSideInset)
            .padding(.top, RMLayout.composerTopInset)
            .padding(.bottom, RMLayout.composerBottomInset)
            .frame(maxWidth: .infinity, minHeight: RMLayout.composerMinimumHeight)
            // Any tap on the card that no control claims focuses the text.
            .contentShape(composerShape)
            .onTapGesture { focus.wrappedValue = true }
            .background { RMPanelBackground(cornerRadius:RMLayout.composerCorner,emphasized:focus.wrappedValue) }
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
        Text("Message").foregroundStyle(RMPalette.secondary)
    }

    private var writingField: some View {
        TextField("Message", text: $text, prompt: prompt, axis: .vertical)
            .font(.body)
            .foregroundStyle(RMPalette.text)
            .tint(RMPalette.text)
            .lineLimit(1...6)
            .submitLabel(.return)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .focused(focus)
            .accessibilityLabel("Message")
            .accessibilityIdentifier("chat.composer.text")
    }

    private var footer: some View {
        HStack(spacing: 0) {
            addButton
            if let reasoningControl { reasoningControl } else if let thinking, let onThinking {
                thinkingButton(isOn: thinking, onToggle: onThinking)
            }
            Spacer(minLength: RMLayout.elementGap)
            actionControls
        }
        .frame(minHeight: RMLayout.minimumHit)
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
        .accessibilityLabel("Message tools and attachments")
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
        .accessibilityLabel("Thinking")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint("Reason step by step before answering")
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
            label: isResponding ? "Stop response" : (offersVoice ? "Voice conversation" : "Send message"),
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
        .accessibilityLabel("Draft attachments")
    }

    /// File tokens share a 44-point row. Image previews keep their own height.
    private var ordinaryAttachmentRow: Bool {
        !dynamicType.isAccessibilitySize
    }
}

/// The composer's single emphatic control. Its geometry never changes; only the
/// glyph and meaning move between voice, send and stop, so the trailing corner
/// stays anchored across states. Stop uses the reference's red fill and subtle glow.
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
                .foregroundStyle(symbol == "stop.fill" ? Color.white : RMPalette.onSend)
                .frame(width: RMLayout.composerSendDiameter, height: RMLayout.composerSendDiameter)
                .background(symbol == "stop.fill" ? Color.red : RMPalette.send, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.28),lineWidth:0.5) }
                .shadow(color: symbol == "stop.fill" ? .red.opacity(0.3) : .black.opacity(0.14), radius: 8, y: 3)
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
        .accessibilityLabel("Attachment: \(attachment.name)")
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
        .accessibilityLabel("Remove \(attachment.name)")
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
