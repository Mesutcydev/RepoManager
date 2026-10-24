// Adapted from OnDeviceMax; see Docs/PROVENANCE.json and LICENSE.
import SwiftUI

/// Keeps the transcript's live reasoning tail and ruled disclosure while adding elapsed time.
public struct RMReasoningBlock: View {
    public let content: String
    public let isOpen: Bool
    public let seconds: Int?
    public let startedAt: Date?
    public let isResponding: Bool
    @State private var expanded: Bool? = nil
    @Environment(\.rmMotionIsReduced) private var reduceMotion

    public init(content: String, isOpen: Bool, seconds: Int? = nil, startedAt: Date? = nil, isResponding: Bool? = nil) {
        self.content = content
        self.isOpen = isOpen
        self.seconds = seconds
        self.startedAt = startedAt
        self.isResponding = isResponding ?? isOpen
    }
    private var showsContent: Bool { expanded ?? isResponding }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded = !showsContent }
            } label: {
                HStack(spacing: RMLayout.elementGap) {
                    if isOpen {
                        if let startedAt {
                            RMTimedActivityLabel(title: "Reasoning…", startedAt: startedAt)
                        } else {
                            HStack(spacing: RMLayout.elementGap) {
                                RMActivityDots()
                                Text("Reasoning…", bundle: .module)
                                    .font(RMType.meta).foregroundStyle(RMPalette.secondary)
                            }
                        }
                    } else {
                        Group {
                            if let seconds { Text("Thought for \(seconds)s", bundle: .module) }
                            else { Text("Thought", bundle: .module) }
                        }
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(RMPalette.secondary)
                    }
                    Rectangle().fill(RMPalette.line).frame(height: 1).accessibilityHidden(true)
                    Text(showsContent ? "Hide" : "Show", bundle: .module)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(RMPalette.secondary)
                }
                .padding(.vertical, RMLayout.unit)
                .frame(minHeight: RMLayout.minimumHit)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsContent ? String(localized:"Expanded",bundle:.module) : String(localized:"Collapsed",bundle:.module))
            .accessibilityIdentifier("chat.reasoning")

            if showsContent {
                Rectangle().fill(RMPalette.line).frame(height: 1)
                    .padding(.vertical, RMLayout.unit).accessibilityHidden(true)
                reasoningText.textSelection(.enabled)
                    .overlay(alignment:.bottomTrailing) {
                        if isOpen { RMStreamingCaret(color:RMPalette.secondary).offset(x:4) }
                    }
            }
        }
    }

    private var reasoningText: some View {
        Text(content)
            .font(.system(size: 14))
            .foregroundStyle(RMPalette.secondary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, RMLayout.elementGap)
    }
}
