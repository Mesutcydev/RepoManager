import SwiftUI

/// The approved sculpted repository-case artwork, shared by navigation and onboarding.
public struct RMBrandGlyph: View {
    public init() {}
    public var body: some View { Image("RMLogo",bundle:.module).resizable().scaledToFit().accessibilityHidden(true) }
}
/// A sentence-case section label, as in native iOS lists.
public struct RMEyebrow: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View { Text(text).font(RMType.label).foregroundStyle(RMPalette.secondary).accessibilityAddTraits(.isHeader) }
}
/// The screen title at the native large-title size, with an optional explanation.
public struct RMPageHeading<Accessory: View>: View {
    let title: String; let detail: String; let accessory: Accessory
    public init(_ title:String,detail:String = "",@ViewBuilder accessory:() -> Accessory) { self.title = title; self.detail = detail; self.accessory = accessory() }
    public var body: some View {
        VStack(alignment:.leading,spacing:RMLayout.unit) {
            HStack(alignment:.center,spacing:RMLayout.elementGap) {
                Text(title).font(RMType.pageTitle).tracking(-0.55).foregroundStyle(RMPalette.text).accessibilityAddTraits(.isHeader)
                    .frame(maxWidth:.infinity,alignment:.leading)
                accessory
            }
            if !detail.isEmpty { Text(detail).font(RMType.detail).foregroundStyle(RMPalette.secondary).fixedSize(horizontal:false,vertical:true) }
        }.frame(maxWidth:.infinity,alignment:.leading)
            .overlay(alignment:.topLeading) {
                Capsule().fill(RMPalette.accent.opacity(0.85)).frame(width:24,height:3).offset(y:-9)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}
extension RMPageHeading where Accessory == EmptyView {
    public init(_ title:String,detail:String = "") { self.init(title,detail:detail) { EmptyView() } }
}

// MARK: Controls. Three heights (36 · 44 · 52); every control is a capsule or a circle.

/// Full-width capsule actions. Primary is filled ink glass, the app's one primary
/// color; secondary is clear glass. Labels grow with Dynamic Type.
private struct RMActionButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        let filled = primary && isEnabled
        configuration.label
            .font(RMType.rowTitle).multilineTextAlignment(.center).lineLimit(2)
            .padding(.horizontal, RMLayout.pageInset).padding(.vertical, RMLayout.rowGap)
            .frame(maxWidth: .infinity, minHeight: RMLayout.controlLarge)
            .foregroundStyle(!isEnabled ? RMPalette.secondary : filled ? RMPalette.onSend : destructive ? RMPalette.red : RMPalette.text)
            .glassEffect(filled ? .regular.tint(destructive ? RMPalette.red : RMPalette.send).interactive() : .regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .modifier(RMControlPressFeedback(pressed:configuration.isPressed))
    }
}
private struct RMTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(RMType.detail.weight(.semibold))
            .foregroundStyle(isEnabled ? (configuration.role == .destructive ? RMPalette.red : RMPalette.accentText) : RMPalette.secondary)
            .frame(minHeight: RMLayout.minimumHit).contentShape(Rectangle())
            .modifier(RMControlPressFeedback(pressed:configuration.isPressed))
    }
}
/// A row-shaped action inside a form: full width, body text, red when destructive.
private struct RMFormRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(RMType.body)
            .foregroundStyle(!isEnabled ? RMPalette.secondary : configuration.role == .destructive ? RMPalette.red : RMPalette.text)
            .frame(maxWidth: .infinity, minHeight: RMLayout.minimumHit, alignment: .leading).contentShape(Rectangle())
            .modifier(RMControlPressFeedback(pressed:configuration.isPressed))
    }
}
/// A 44-pt glass circle, the iOS 26 toolbar control.
private struct RMIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo:.body) private var glyphSize: CGFloat = 17
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:min(glyphSize,RMLayout.glyphMaximum),weight:.medium))
            .foregroundStyle(isEnabled ? RMPalette.text : RMPalette.secondary)
            .frame(width: RMLayout.minimumHit, height: RMLayout.minimumHit)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .modifier(RMControlPressFeedback(pressed:configuration.isPressed))
    }
}
/// A 36-pt glass capsule for context such as the model, repository and branch.
private struct RMChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(RMType.detail.weight(.semibold)).lineLimit(1)
            .foregroundStyle(isEnabled ? RMPalette.text : RMPalette.secondary)
            .padding(.horizontal, RMLayout.rowGap)
            .frame(minHeight: RMLayout.controlCompact)
            .glassEffect(.regular.interactive(), in: Capsule())
            .frame(minHeight: RMLayout.minimumHit).contentShape(Rectangle())
            .modifier(RMControlPressFeedback(pressed:configuration.isPressed))
    }
}
extension View {
    /// The screen's primary action, with a consistent full-width target.
    public func rmProminentButton() -> some View { buttonStyle(RMActionButtonStyle(primary: true)) }
    public func rmSecondaryButton() -> some View { buttonStyle(RMActionButtonStyle(primary: false)) }
    public func rmTextButton() -> some View { buttonStyle(RMTextButtonStyle()) }
    public func rmIconButton() -> some View { buttonStyle(RMIconButtonStyle()) }
    public func rmChip() -> some View { buttonStyle(RMChipButtonStyle()) }
    /// A text input at the large control height, on the input fill.
    public func rmField() -> some View {
        font(RMType.body).padding(.horizontal, RMLayout.pageInset)
            .frame(minHeight: RMLayout.controlLarge)
            .background(RMPalette.input, in: Capsule())
    }
    /// A raised card. Its corner is concentric with a tile inset by the card padding.
    public func rmSurface() -> some View {
        background { RMPanelBackground() }
    }
}

// MARK: Rows. A 32-pt tile, 16-pt card inset and 24-pt card corner: 8 + 16 = 24.

/// A squircle glyph tile. Neutral by default; a tint marks state, never decoration.
public struct RMIconTile: View {
    let symbol: String; let tint: Color?; let size: CGFloat
    @Environment(\.rmMotionIsReduced) private var reduced
    public init(_ symbol: String, tint: Color? = nil, size: CGFloat = RMLayout.tile) { self.symbol = symbol; self.tint = tint; self.size = size }
    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.47, weight: .semibold))
            .foregroundStyle(tint ?? RMPalette.text)
            .frame(width: size, height: size)
            .background((tint ?? RMPalette.text).opacity(tint == nil ? 0.08 : 0.14), in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius:size/4,style:.continuous)
                    .strokeBorder(LinearGradient(colors:[.white.opacity(0.2),RMPalette.line.opacity(0.2)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.5)
            }
            .shadow(color:.black.opacity(0.08),radius:3,y:2)
            .contentTransition(reduced ? .opacity : .symbolEffect(.replace))
            .animation(reduced ? nil : .easeOut(duration:0.18),value:symbol)
            .accessibilityHidden(true)
    }
}
/// An ink monogram for an account or provider: the same squircle as a tile.
public struct RMMonogram: View {
    let text: String; let size: CGFloat
    public init(_ text: String, size: CGFloat = RMLayout.tile) { self.text = text; self.size = size }
    public var body: some View {
        Text(String(text.prefix(1)).uppercased())
            .font(.system(size: size * 0.47, weight: .bold, design: .rounded))
            .foregroundStyle(RMPalette.onSend)
            .frame(width: size, height: size)
            .background(RMPalette.send, in: RoundedRectangle(cornerRadius: size / 4, style: .continuous))
            .accessibilityHidden(true)
    }
}
public enum RMRowAccessory { case none, chevron, selected(Bool), value(String) }
/// The one row: tile, title, optional detail, trailing accessory. 64 pt minimum.
public struct RMRow<Leading: View, Trailing: View>: View {
    let title: String; let detail: String?; let accessory: RMRowAccessory
    let leading: Leading; let trailing: Trailing
    public init(_ title: String, detail: String? = nil, accessory: RMRowAccessory = .none,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.detail = detail; self.accessory = accessory; self.leading = leading(); self.trailing = trailing()
    }
    public var body: some View {
        HStack(spacing: RMLayout.rowGap) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(RMType.rowTitle).foregroundStyle(RMPalette.text).multilineTextAlignment(.leading)
                if let detail, !detail.isEmpty {
                    Text(detail).font(RMType.detail).foregroundStyle(RMPalette.secondary).multilineTextAlignment(.leading).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            trailing
            switch accessory {
            case .none: EmptyView()
            case .chevron: Image(systemName: "chevron.forward").font(RMType.label).foregroundStyle(RMPalette.secondary).accessibilityHidden(true)
            case .selected(let on):
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(on ? RMPalette.accentText : RMPalette.line).accessibilityHidden(true)
            case .value(let value): Text(value).font(RMType.detail).foregroundStyle(RMPalette.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, RMLayout.cardInset).padding(.vertical, RMLayout.rowGap)
        .frame(maxWidth: .infinity, minHeight: RMLayout.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
        // Combined for VoiceOver, unless trailing controls must stay reachable on their own.
        .accessibilityElement(children: Trailing.self == EmptyView.self ? .combine : .contain)
        .accessibilityAddTraits({ if case .selected(true) = accessory { return .isSelected }; return [] }())
    }
}
extension RMRow where Leading == RMIconTile, Trailing == EmptyView {
    public init(_ title: String, detail: String? = nil, symbol: String, tint: Color? = nil, accessory: RMRowAccessory = .none) {
        self.init(title, detail: detail, accessory: accessory) { RMIconTile(symbol, tint: tint) } trailing: { EmptyView() }
    }
}
extension RMRow where Leading == EmptyView, Trailing == EmptyView {
    public init(_ title: String, detail: String? = nil, accessory: RMRowAccessory = .none) {
        self.init(title, detail: detail, accessory: accessory) { EmptyView() } trailing: { EmptyView() }
    }
}
/// Rows grouped on one card, separated by hairlines that start where row text starts.
public struct RMCard<Content: View>: View {
    let header: String?; let footer: String?; let dividerInset: CGFloat; let content: Content
    public init(_ header: String? = nil, dividerInset: CGFloat = RMLayout.dividerInset, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.header = header; self.footer = footer; self.dividerInset = dividerInset; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.elementGap) {
            if let header { RMEyebrow(header).padding(.horizontal, RMLayout.cardInset) }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        if row.id != rows.first?.id { Rectangle().fill(RMPalette.line).frame(height: 0.5).padding(.leading, dividerInset) }
                        row
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: RMLayout.cardCorner, style: .continuous))
            .rmSurface()
            if let footer {
                Text(footer).font(RMType.meta).foregroundStyle(RMPalette.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, RMLayout.cardInset)
            }
        }
    }
}
/// A static status capsule: 13-pt label, 4-pt vertical and 8-pt horizontal insets (24 pt tall).
/// Neutral by default; a tint marks state.
public struct RMBadge: View {
    let text: String; let symbol: String?; let tint: Color?
    @Environment(\.rmMotionIsReduced) private var reduced
    public init(_ text: String, symbol: String? = nil, tint: Color? = nil) { self.text = text; self.symbol = symbol; self.tint = tint }
    public var body: some View {
        HStack(spacing: RMLayout.unit) {
            if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
            Text(text).lineLimit(1)
                .contentTransition(.opacity)
        }
        .font(RMType.label).foregroundStyle(tint ?? RMPalette.secondary)
        .padding(.horizontal, RMLayout.elementGap).padding(.vertical, RMLayout.unit)
        .background((tint ?? RMPalette.text).opacity(tint == nil ? 0.08 : 0.14), in: Capsule())
        .overlay { Capsule().strokeBorder((tint ?? RMPalette.line).opacity(0.3),lineWidth:0.5) }
        .animation(reduced ? nil : .easeOut(duration:0.18),value:text)
    }
}
/// Form labels render as tiled rows, so native Settings-style lists match the cards.
public struct RMTileLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: RMLayout.rowGap) {
            configuration.icon.font(.system(size: RMLayout.tile * 0.47, weight: .semibold)).foregroundStyle(RMPalette.text)
                .frame(width: RMLayout.tile, height: RMLayout.tile)
                .background(RMPalette.text.opacity(0.08), in: RoundedRectangle(cornerRadius: RMLayout.tileCorner, style: .continuous))
            configuration.title
        }
    }
}

// MARK: Composite views.

public struct RMInlineNotice: View {
    let title: LocalizedStringKey
    let detail: String
    let symbol: String
    let isError: Bool
    public init(title: LocalizedStringKey, detail: String, symbol: String, isError: Bool = false) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.isError = isError
    }
    public var body: some View {
        HStack(alignment: .top, spacing: RMLayout.rowGap) {
            RMIconTile(symbol, tint: isError ? RMPalette.red : nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(title, bundle:.main).font(RMType.rowTitle).foregroundStyle(RMPalette.text)
                Text(detail).font(RMType.detail).foregroundStyle(RMPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(RMLayout.cardInset).frame(maxWidth: .infinity, alignment: .leading).rmSurface()
            .accessibilityElement(children: .combine)
    }
}
/// Native form grouping on the same palette, row height and tile as the cards.
public struct RMForm<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        Form { content.listRowBackground(RMPalette.surface).listRowSeparatorTint(RMPalette.line) }
            .scrollContentBackground(.hidden).background(RMPageBackground())
            .environment(\.defaultMinListRowHeight, RMLayout.controlLarge)
            .listSectionSpacing(RMLayout.groupGap)
            .labelStyle(RMTileLabelStyle())
            .tint(RMPalette.accentText)
            .buttonStyle(RMFormRowButtonStyle())
    }
}
public struct RMEmptyState: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String?
    public init(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String? = nil) {
        self.title = title; self.detail = detail; self.symbol = symbol
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: RMLayout.cardInset) {
            if let symbol { RMIconTile(symbol, size: RMLayout.heroTile) }
            VStack(alignment: .leading, spacing: RMLayout.unit) {
                Text(title, bundle:.main).font(RMType.title).foregroundStyle(RMPalette.text)
                Text(detail).font(RMType.detail).foregroundStyle(RMPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        // On the page itself, not a card: an empty state is not content.
        }.padding(.vertical, RMLayout.elementGap).frame(maxWidth: .infinity, alignment: .leading)
    }
}
