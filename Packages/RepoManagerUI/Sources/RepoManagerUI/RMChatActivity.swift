// Adapted from OnDeviceMax; see Docs/PROVENANCE.json and LICENSE.
import SwiftUI
import UIKit
import RepoManagerCore

/// Shared chat activity surfaces. The host supplies real events and timestamps.
public struct RMToolEvent: Identifiable, Equatable {
    public enum Status: String, Equatable { case running, success, failure, cancelled, approval }
    public let id: String
    public var title: String
    public var detail: String
    public var status: Status
    public var arguments: String?

    public init(id: String = UUID().uuidString, title: String, detail: String = "", status: Status, arguments: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.arguments = arguments
    }
}

/// A single disclosure owns the tool list; large logs stay in the transcript's
/// vertical scroll, and full output opens in a selectable native detail sheet.
public struct RMToolActivityGroup: View {
    public let events: [RMToolEvent]
    public let isRunning: Bool
    @Binding private var expanded: Bool
    @State private var collapsedWhileRunning = false
    @State private var selected: RMToolEvent?
    public init(events: [RMToolEvent], isRunning: Bool, expanded: Binding<Bool>) {
        self.events = events; self.isRunning = isRunning; self._expanded = expanded
    }
    private var isOpen: Bool { expanded || isRunning && !collapsedWhileRunning }
    private var failed: Int { events.filter { $0.status == .failure }.count }
    private var complete: Int { events.filter { [.success, .failure, .cancelled].contains($0.status) }.count }
    public var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.unit) {
            Button {
                let next = !isOpen; expanded = next; collapsedWhileRunning = !next
            } label: {
                HStack(spacing: RMLayout.elementGap) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.caption2.weight(.semibold))
                    if isRunning { Text("Using tools · \(complete) complete", bundle: .module) }
                    else { Text("Used \(events.count) tools", bundle: .module) }
                    if failed > 0 { Label { Text("\(failed) failed", bundle: .module) } icon: { Image(systemName: "exclamationmark.circle") }.foregroundStyle(RMPalette.red) }
                    Spacer(minLength: 0)
                }.font(RMType.meta).foregroundStyle(RMPalette.secondary).frame(minHeight: RMLayout.minimumHit).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityValue(isOpen ? String(localized: "Expanded", bundle: .module) : String(localized: "Collapsed", bundle: .module))
            .accessibilityIdentifier("chat.tools.summary")
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        RMToolActivityRow(event: event) { selected = event }
                        if event.id != events.last?.id { Divider().padding(.leading, RMLayout.rowGap) }
                    }
                }.background { RMFrostedPanelBackground(cornerRadius: RMLayout.rowCorner) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chat.tools")
            }
        }.sheet(item: $selected) { RMToolActivityDetail(event: $0) }
    }
}

private struct RMToolActivityRow: View {
    let event: RMToolEvent
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: RMLayout.elementGap) {
                Image(systemName: symbol).foregroundStyle(event.status == .failure ? RMPalette.red : RMPalette.secondary)
                    .frame(width: 18).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: RMLayout.unit) {
                    Text(event.title).font(.system(.footnote, design: .monospaced)).lineLimit(2)
                    if event.status == .failure { Text("Failed — open details", bundle: .module).font(RMType.meta).foregroundStyle(RMPalette.red) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
            }.foregroundStyle(RMPalette.text).padding(RMLayout.rowGap).frame(minHeight: RMLayout.minimumHit).contentShape(Rectangle())
        }.buttonStyle(RMPressButtonStyle()).accessibilityLabel(event.title).accessibilityValue(RMLocalization.text(event.status.rawValue))
            .accessibilityHint(Text("Shows tool details", bundle: .module)).accessibilityIdentifier("chat.tool.\(event.id)")
    }
    private var symbol: String {
        switch event.status {
        case .running: "circle.dotted"
        case .success: "checkmark.circle"
        case .failure: "exclamationmark.circle"
        case .cancelled: "minus.circle"
        case .approval: "checkmark.shield"
        }
    }
}

private struct RMToolActivityDetail: View {
    let event: RMToolEvent
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RMLayout.cardInset) {
                    LabeledContent { Text(RMLocalization.text(event.status.rawValue)) } label: { Text("Status", bundle: .module) }.font(RMType.body)
                    if let arguments = event.arguments, !arguments.isEmpty {
                        Text("Arguments", bundle: .module).font(RMType.label)
                        Text(arguments).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    }
                    Text("Output", bundle: .module).font(RMType.label)
                    Text(event.detail.isEmpty ? event.title : event.detail).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("chat.tool.details")
                    Button {
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: [event.arguments, event.detail].compactMap { $0 }.joined(separator: "\n\n")]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                        copied = true
                    } label: { Label { Text(copied ? "Copied" : "Copy details", bundle: .module) } icon: { Image(systemName: copied ? "checkmark" : "doc.on.doc") } }
                        .rmSecondaryButton().accessibilityIdentifier("chat.tool.copy")
                }.padding(RMLayout.pageInset).frame(maxWidth: .infinity, alignment: .leading)
            }.navigationTitle(event.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button { dismiss() } label: { Label { Text("Done", bundle: .module) } icon: { Image(systemName: "checkmark") } }.accessibilityIdentifier("chat.tool.done") } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationBackground(.thinMaterial)
    }
}

public struct RMAgentLabel: View {
    public init() {}
    public var body: some View {
        Text("AGENT", bundle: .module)
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(RMPalette.secondary)
            .accessibilityLabel(Text("Assistant", bundle: .module))
    }
}

/// The existing reply bar, shared by answer text and live reasoning.
public struct RMStreamingCaret: View {
    public let color: Color
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rmWorkspaceVisible) private var workspaceVisible
    @ScaledMetric(relativeTo: .body) private var caretHeight: CGFloat = 16

    public init(color: Color = RMPalette.text) { self.color = color }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15,
                                paused: reduceMotion || !workspaceVisible || scenePhase != .active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * .pi * 2 / 1.2
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 2, height: caretHeight)
                .opacity(reduceMotion ? 0.65 : 0.35 + 0.65 * (sin(phase) + 1) / 2)
        }
        .accessibilityHidden(true)
    }
}

/// Lightweight streaming layout; only the caret animates between token updates.
public struct RMStreamingText: View {
    public let content: String
    public let font: Font
    public let color: Color
    public let lineSpacing: CGFloat

    public init(content: String, font: Font = .body, color: Color = RMPalette.text, lineSpacing: CGFloat = 4) {
        self.content = content
        self.font = font
        self.color = color
        self.lineSpacing = lineSpacing
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(content)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.disabled)
            RMStreamingCaret(color: color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("Streaming", bundle: .module))
        .accessibilityIdentifier("chat.reply.streaming")
    }
}

public struct RMToolPillStrip: View {
    public let events: [RMToolEvent]
    @State private var selectedEvent: RMToolEvent?
    @ScaledMetric(relativeTo: .caption2) private var titleMaximumWidth = 210
    public init(events: [RMToolEvent]) { self.events = events }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RMLayout.unit) {
                ForEach(events) { event in
                    Button { selectedEvent = event } label: {
                        HStack(spacing: RMLayout.unit) {
                            statusIcon(event.status)
                                .frame(width:16,height:16)
                            Text(event.title)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(RMPalette.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: titleMaximumWidth, alignment: .leading)
                        }
                        .font(RMType.meta)
                        .padding(.horizontal, RMLayout.elementGap)
                        .padding(.vertical, RMLayout.unit)
                        .background(RMPalette.input, in: Capsule())
                        .overlay { Capsule().strokeBorder(RMPalette.line, lineWidth: 1) }
                        .fixedSize()
                        .frame(minHeight: RMLayout.minimumHit)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(event.title)
                    .accessibilityValue(RMLocalization.text(event.status.rawValue))
                    .accessibilityHint(Text("Shows tool details", bundle: .module))
                    .accessibilityIdentifier("chat.tool.\(event.id)")
                }
            }
        }
        .frame(minHeight: RMLayout.minimumHit)
        .accessibilityIdentifier("chat.tools")
        .sheet(item: $selectedEvent) { event in
            NavigationStack {
                ScrollView {
                    Text(event.detail.isEmpty ? event.title : event.detail)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .accessibilityIdentifier("chat.tool.details")
                }
                .navigationTitle(event.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { selectedEvent = nil } label: { Text("Done", bundle: .module) }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private func statusIcon(_ status: RMToolEvent.Status) -> some View {
        switch status {
        case .running:
            ProgressView().controlSize(.mini).accessibilityHidden(true)
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.59)).accessibilityHidden(true)
        case .failure:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red).accessibilityHidden(true)
        case .approval:
            Image(systemName: "checkmark.shield").foregroundStyle(Color.orange).accessibilityHidden(true)
        case .cancelled:
            Image(systemName: "minus.circle.fill").foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
        }
    }
}

/// Only this small view redraws for the dots; transcript text is not re-laid out.
public struct RMActivityDots: View {
    @Environment(\.rmMotionIsReduced) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rmWorkspaceVisible) private var workspaceVisible
    public init() {}

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30,
                                paused: reduceMotion || !workspaceVisible || scenePhase != .active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: RMLayout.unit) {
                ForEach(0..<3) { index in
                    let wave = reduceMotion ? 0 : max(0, sin(time * .pi * 2 - Double(index) * 0.9))
                    Circle()
                        .fill(RMPalette.secondary)
                        .frame(width: 6, height: 6)
                        .offset(y: -3 * wave)
                        .opacity(reduceMotion ? 0.7 : 0.55 + 0.45 * wave)
                }
            }
            .frame(height: 12)
        }
        .accessibilityHidden(true)
    }
}

public struct RMTimedActivityLabel: View {
    public let title: String
    public let startedAt: Date
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.rmWorkspaceVisible) private var workspaceVisible

    public init(title: String, startedAt: Date) {
        self.title = title
        self.startedAt = startedAt
    }

    public var body: some View {
        HStack(spacing: RMLayout.elementGap) {
            RMActivityDots()
            TimelineView(.animation(minimumInterval: 1, paused: !workspaceVisible || scenePhase != .active)) { context in
                let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text("\(title) · \(seconds)s", bundle:.module)
                    .font(RMType.label)
                    .monospacedDigit()
                    .foregroundStyle(RMPalette.secondary)
                    .accessibilityIdentifier("chat.activity.timer")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public struct RMContextCompactionBanner: View {
    public let message: String
    @ScaledMetric(relativeTo: .caption) private var iconWidth: CGFloat = 16

    public init(message: String) { self.message = message }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RMLayout.elementGap) {
            Image(systemName: "rectangle.compress.vertical")
                .font(RMType.meta.weight(.medium))
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(RMType.meta)
        .foregroundStyle(RMPalette.secondary)
        .padding(.horizontal, RMLayout.rowGap)
        .padding(.vertical, RMLayout.elementGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RMPalette.input, in: RoundedRectangle(cornerRadius: RMLayout.rowCorner, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Context compacted", bundle: .module))
        .accessibilityValue(message)
        .accessibilityIdentifier("chat.contextCompaction")
    }
}
