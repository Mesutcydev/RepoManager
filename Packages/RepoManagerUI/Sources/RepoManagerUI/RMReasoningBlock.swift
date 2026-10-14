// Adapted from OnDeviceMax; see Docs/PROVENANCE.json and LICENSE.
import SwiftUI

/// Keeps the transcript's live reasoning tail and ruled disclosure while adding elapsed time.
public struct RMReasoningBlock: View {
    public let content: String
    public let isOpen: Bool
    public let seconds: Int?
    public let startedAt: Date?
    @State private var expanded = false
    @Environment(\.rmMotionIsReduced) private var reduceMotion

    public init(content: String, isOpen: Bool, seconds: Int? = nil, startedAt: Date? = nil) {
        self.content = content
        self.isOpen = isOpen
        self.seconds = seconds
        self.startedAt = startedAt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { expanded.toggle() }
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
                    if isOpen && !expanded {
                        RMStreamingText(content: "", font: .footnote, color: RMPalette.secondary)
                            .fixedSize()
                    }
                    Rectangle().fill(RMPalette.line).frame(height: 1).accessibilityHidden(true)
                    Text(expanded ? "Hide" : "Show", bundle: .module)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(RMPalette.secondary)
                }
                .padding(.vertical, RMLayout.unit)
                .frame(minHeight: RMLayout.minimumHit)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("chat.reasoning")

            if expanded && isOpen {
                RMStreamingText(content: content, font: .system(size: 14),
                                color: RMPalette.secondary, lineSpacing: 5)
                    .padding(.top, content.isEmpty ? 4 : 6)
                    .padding(.bottom, RMLayout.elementGap)
            } else if expanded {
                Rectangle().fill(RMPalette.line).frame(height: 1)
                    .padding(.vertical, RMLayout.unit).accessibilityHidden(true)
                reasoningText.textSelection(.enabled)
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
            .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
