import SwiftUI

public struct RMAttachment: Identifiable, Equatable {
    public var id: String; public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public enum RMWorkspace: String, CaseIterable, Identifiable {
    case chats, chat, repositories, changes, issues, pullRequests, actions, releases, security, activity, providers, tools, voice, apiServer
    public var id: String { rawValue }
    public var title: String {
        switch self { case .pullRequests: "Pull requests"; case .apiServer: "API server"; default: rawValue.capitalized }
    }
    public var symbol: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"; case .chat: "bubble.left"; case .repositories: "folder"
        case .changes: "square.and.pencil"; case .issues: "circle.dotted"; case .pullRequests: "arrow.triangle.pull"
        case .actions: "play.circle"; case .releases: "tag"; case .security: "lock.shield"; case .activity: "tray"
        case .providers: "server.rack"; case .tools: "wrench.and.screwdriver"; case .voice: "waveform"; case .apiServer: "network"
        }
    }
}
private struct RMWorkspaceVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    public var rmWorkspaceVisible: Bool { get { self[RMWorkspaceVisibleKey.self] } set { self[RMWorkspaceVisibleKey.self] = newValue } }
}
public struct RMPressButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(RMControlPressFeedback(pressed:configuration.isPressed))
    }
}
/// A recent conversation shown in the drawer. The host owns storage and selection.
public struct RMRecentChat: Identifiable, Equatable {
    public let id: String; public let title: String; public let detail: String
    public init(id: String, title: String, detail: String) { self.id = id; self.title = title; self.detail = detail }
}

/// OnDeviceMax's push drawer: the workspace becomes a card that slides aside over a
/// parallax drawer. Visited workspaces stay mounted so drafts and scroll positions survive.
public struct RMWorkbench: View {
    @Binding private var selection: RMWorkspace
    @State private var visited: Set<RMWorkspace> = [.chats,.chat]
    /// `drawer` is the intent; `drawerOpen` is its animated mirror, and the drawer
    /// stays mounted until its close spring finishes.
    @State private var drawer = false
    @State private var drawerOpen = false
    @State private var drawerMounted = false
    @GestureState(resetTransaction: Transaction(animation: RMWorkbench.spring)) private var dragOffset: CGFloat = 0
    @Environment(\.layoutDirection) private var direction
    @Environment(\.rmMotionIsReduced) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.rmAppearance) private var appearance
    private let recents: [RMRecentChat]; private let currentRecentID: String?
    private let openRecent: (String) -> Void
    private let content: (RMWorkspace) -> AnyView
    private let settings: () -> Void; private let newChat: () -> Void
    private let principal: (RMWorkspace) -> AnyView?
    private let actions: (RMWorkspace) -> AnyView?
    /// Critically damped: the card settles without a wobble.
    static let spring: Animation = .spring(response: 0.44, dampingFraction: 0.9)
    /// Close to the iPhone display radius, so the card reads as the screen itself.
    private static let cardCorner: CGFloat = 55
    public init(selection: Binding<RMWorkspace>, recents: [RMRecentChat] = [], currentRecentID: String? = nil,
                openRecent: @escaping (String) -> Void = { _ in }, settings: @escaping () -> Void,
                newChat: @escaping () -> Void, principal: @escaping (RMWorkspace) -> AnyView? = { _ in nil },
                actions: @escaping (RMWorkspace) -> AnyView? = { _ in nil },
                content: @escaping (RMWorkspace) -> AnyView) {
        self.principal = principal; self.actions = actions; _selection = selection; self.recents = recents; self.currentRecentID = currentRecentID; self.openRecent = openRecent
        self.settings = settings; self.newChat = newChat; self.content = content
    }
    public var body: some View {
        GeometryReader { geometry in
            let width = typeSize.isAccessibilitySize ? min(480, max(0, geometry.size.width - 24)) : RMLayout.drawerWidth(availableWidth: geometry.size.width)
            let offset = min(width, max(0, (drawerOpen ? width : 0) + dragOffset))
            let progress = width > 0 ? offset / width : 0
            // Gesture translations are physical; offsets below are leading-relative and SwiftUI mirrors them in RTL.
            let sign: CGFloat = direction == .leftToRight ? 1 : -1
            let corner = Self.cardCorner * min(1, progress * 3)
            ZStack(alignment: .leading) {
                if drawerMounted || dragOffset > 0 {
                    RMDrawer(selection: selection, recents: recents, currentRecentID: currentRecentID,
                             go: { page in visited.insert(page); selection = page; close() },
                             openRecent: { id in openRecent(id); close() },
                             settings: { close(); settings() }, newChat: { close(); newChat() })
                        .frame(width: width).frame(maxHeight: .infinity)
                        // Parallax: the drawer eases in from a quarter of its width behind the card.
                        .offset(x: reduced ? 0 : -(1 - progress) * width * 0.25)
                        .opacity(reduced ? (drawerOpen ? 1 : 0) : 0.35 + 0.65 * progress)
                        .accessibilityHidden(!drawer).allowsHitTesting(drawer)
                        .accessibilityAction(.escape) { close() }
                        .simultaneousGesture(dragGesture(width: width, sign: sign))
                }
                workspace
                    .background { RMPageBackground() }
                    .overlay {
                        // No dimming: the card keeps full brightness. Tapping it closes the drawer.
                        if drawer {
                            Button { close() } label: { Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity, maxHeight: .infinity) }
                                .buttonStyle(.plain).accessibilityLabel("Close sidebar").accessibilityIdentifier("navigation.dismissMenu")
                                .gesture(dragGesture(width: width, sign: sign))
                        }
                    }
                    // The mask reaches into the status-bar and home-indicator areas so the
                    // card's corners sit at the screen edges, not the safe-area edges.
                    .mask {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .padding(.top, -geometry.safeAreaInsets.top).padding(.bottom, -geometry.safeAreaInsets.bottom)
                    }
                    .overlay {
                        // OLED card and drawer are both black; a hairline separates them.
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(appearance == .oled ? RMPalette.line : .clear, lineWidth: 1)
                            .padding(.top, -geometry.safeAreaInsets.top).padding(.bottom, -geometry.safeAreaInsets.bottom)
                            .opacity(progress).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .shadow(color: .black.opacity(0.22 * progress), radius: 30, x: -8 * sign)
                    .offset(x: reduced ? (drawerOpen ? width : 0) : offset)
                    .zIndex(1)
                if !drawer {
                    // Leading-edge strip: a swipe from the edge opens the drawer.
                    Color.clear.frame(width: 20).contentShape(Rectangle())
                        .gesture(dragGesture(width: width, sign: sign)).accessibilityHidden(true).zIndex(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Behind the card, so its rounded corners cut out to the drawer color.
        .background { RMDrawerBackdrop() }
        .onChange(of: drawer, initial: true) { _, open in
            if open { drawerMounted = true }
            withAnimation(reduced ? .easeInOut(duration: 0.18) : Self.spring) { drawerOpen = open } completion: { if !drawer { drawerMounted = false } }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: drawer)
        .onChange(of: selection, initial: true) { _, value in visited.insert(value) }
    }
    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: RMLayout.elementGap) {
                Button { drawer = true } label: { RMMenuMark() }
                    .rmIconButton()
                    .accessibilityHidden(drawer)
                    .accessibilityLabel("Open sidebar").accessibilityIdentifier("navigation.sidebar")
                Spacer(minLength: 0)
                if !drawer, let trailing = actions(selection) { trailing }
                Button(action: newChat) { Image(systemName: "square.and.pencil") }
                    .rmIconButton()
                    .accessibilityHidden(drawer)
                    .accessibilityLabel("New chat").accessibilityIdentifier("navigation.newChat")
            }
            // The principal is centered on the bar, clear of the widest side: two 44-pt circles and a gap.
            .overlay {
                // SwiftUI's nested native presentation host can retain a
                // principal button in AX despite ancestor accessibilityHidden.
                // Remove that control while the modal drawer owns focus.
                if !drawer, let center = principal(selection) {
                    center.padding(.horizontal, 2 * RMLayout.minimumHit + 2 * RMLayout.elementGap)
                }
            }
            .foregroundStyle(RMPalette.text).padding(.horizontal, RMLayout.pageInset).padding(.bottom, RMLayout.elementGap)
            ZStack {
                ForEach(RMWorkspace.allCases.filter { visited.contains($0) }) { page in
                    RMMountedWorkspace(content: content(page), visible: selection == page, interactive: !drawer)
                        .opacity(selection == page ? 1 : 0)
                        .allowsHitTesting(selection == page && !drawer)
                        .accessibilityHidden(selection != page || drawer)
                        .zIndex(selection == page ? 1 : 0)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(!drawer).accessibilityHidden(drawer)
    }
    private func dragGesture(width: CGFloat, sign: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width * sign
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                drawer = (drawer ? width : 0) + value.predictedEndTranslation.width * sign > width * 0.5
            }
    }
    private func close() { drawer = false }
}

/// The two-line menu mark from OnDeviceMax, drawn natively rather than from an SF Symbol.
struct RMMenuMark: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().frame(width: 20, height: 2)
            Capsule().frame(width: 13, height: 2)
        }.frame(width: 20, height: 20, alignment: .leading)
    }
}

/// Brand and Settings at the head, destinations as a compact grid, recent chats as
/// the body, and Search and New chat at the foot.
private struct RMDrawer: View {
    let selection: RMWorkspace; let recents: [RMRecentChat]; let currentRecentID: String?
    let go: (RMWorkspace) -> Void; let openRecent: (String) -> Void
    let settings: () -> Void; let newChat: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private let destinations: [RMWorkspace] = [.repositories,.changes,.pullRequests,.issues,.actions,.releases,.security,.activity,.providers,.tools,.voice,.apiServer]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: RMLayout.rowGap) {
                RMBrandGlyph().frame(width: RMLayout.tile, height: RMLayout.tile)
                Text("Repo Manager").font(RMType.title).fixedSize(horizontal:false,vertical:true)
                    .accessibilityAddTraits(.isHeader).frame(maxWidth: .infinity, alignment: .leading)
                RMGlassIconButton("gearshape", label: "Settings", action: settings).accessibilityIdentifier("navigation.settings")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: RMLayout.groupGap) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: RMLayout.elementGap), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: RMLayout.elementGap) {
                        ForEach(destinations) { page in RMDrawerTile(page: page, selected: selection == page) { go(page) } }
                    }
                    recentsSection
                }.padding(.top, RMLayout.pageInset).padding(.bottom, RMLayout.groupGap)
            }.scrollIndicators(.hidden).accessibilityIdentifier("navigation.drawerScroll")
            footer
        }
        .padding(.horizontal, RMLayout.pageInset).padding(.bottom, RMLayout.elementGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // One step below the page, so the workspace reads as a card resting on it.
        .background { RMDrawerBackdrop() }
        .foregroundStyle(RMPalette.text)
        .accessibilityElement(children: .contain).accessibilityLabel("App navigation").accessibilityIdentifier("navigation.drawer")
    }
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: RMLayout.unit) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recents").font(RMType.rowTitle).accessibilityAddTraits(.isHeader)
                Spacer(minLength: RMLayout.elementGap)
                Button { go(.chats) } label: {
                    HStack(spacing: RMLayout.unit) { Text("All chats"); Image(systemName: "chevron.forward").font(RMType.label).accessibilityHidden(true) }
                        .font(RMType.detail).foregroundStyle(RMPalette.secondary).frame(minHeight: RMLayout.minimumHit).contentShape(Rectangle())
                }.buttonStyle(RMPressButtonStyle()).accessibilityIdentifier("navigation.chats")
            }
            if recents.isEmpty { Text("Your chats appear here.").font(RMType.detail).foregroundStyle(RMPalette.secondary).padding(.vertical, RMLayout.elementGap) }
            ForEach(recents) { chat in
                let current = selection == .chat && chat.id == currentRecentID
                Button { openRecent(chat.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.title).font(RMType.body).lineLimit(1)
                        if !chat.detail.isEmpty { Text(chat.detail).font(RMType.detail).foregroundStyle(RMPalette.secondary).lineLimit(1) }
                    }
                    .padding(.horizontal, RMLayout.rowGap).padding(.vertical, RMLayout.elementGap)
                    .frame(maxWidth: .infinity, minHeight: RMLayout.controlLarge, alignment: .leading)
                    .background(current ? RMPalette.surface : .clear, in: RoundedRectangle(cornerRadius: RMLayout.rowCorner, style: .continuous))
                    .contentShape(Rectangle())
                }.buttonStyle(RMPressButtonStyle()).accessibilityAddTraits(current ? .isSelected : []).accessibilityIdentifier("navigation.recent.\(chat.id)")
                    .padding(.horizontal, -RMLayout.rowGap)
            }
        }
    }
    private var footer: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: RMLayout.elementGap)) : AnyLayout(HStackLayout(spacing: RMLayout.elementGap))) {
            RMGlassIconButton("magnifyingglass", label: "Search chats") { go(.chats) }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Button(action: newChat) { Label("New chat", systemImage: "square.and.pencil").font(.body.weight(.semibold)).lineLimit(1) }
                .rmProminentButton().accessibilityIdentifier("navigation.drawerNewChat")
        }.padding(.top, RMLayout.elementGap)
    }
}

private struct RMDrawerTile: View {
    let page: RMWorkspace; let selected: Bool; let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.rmMotionIsReduced) private var reduced
    @ScaledMetric(relativeTo:.body) private var glyphSize = 20
    var body: some View {
        Button(action: action) {
            (typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: RMLayout.rowGap)) : AnyLayout(VStackLayout(spacing: RMLayout.unit))) {
                Image(systemName: page.symbol).font(.system(size:min(glyphSize,RMLayout.glyphMaximum),weight:.medium))
                    .foregroundStyle(selected ? RMPalette.accentText : RMPalette.text)
                    .frame(width:RMLayout.glyphMaximum,height:RMLayout.glyphMaximum).accessibilityHidden(true)
                Text(page.title).font(RMType.meta.weight(.medium)).lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }
            .padding(.horizontal, RMLayout.elementGap).frame(maxWidth: .infinity, minHeight: RMLayout.rowHeight)
            .foregroundStyle(RMPalette.text)
            .background { RMPanelBackground(cornerRadius:RMLayout.rowCorner,emphasized:selected,fill:selected ? RMPalette.accentSoft : RMPalette.surface) }
            .overlay { if selected { RoundedRectangle(cornerRadius:RMLayout.rowCorner,style:.continuous).strokeBorder(RMPalette.accent.opacity(0.55),lineWidth:1) } }
            .animation(reduced ? nil : .easeOut(duration:0.18),value:selected)
            .contentShape(RoundedRectangle(cornerRadius: RMLayout.rowCorner, style: .continuous))
        }
        .buttonStyle(RMPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("navigation.\(page.rawValue)")
    }
}

/// Black in OLED, otherwise one palette step below the page.
private struct RMDrawerBackdrop: View {
    @Environment(\.rmAppearance) private var appearance
    var body: some View {
        ZStack {
            appearance == .oled ? Color.black : RMPalette.chrome
            if appearance != .oled { RadialGradient(colors:[RMPalette.accent.opacity(0.08),.clear],center:.topLeading,startRadius:0,endRadius:380) }
        }.ignoresSafeArea()
    }
}

/// A toolbar icon using the same target and shape as other workspace actions.
public struct RMGlassIconButton: View {
    let symbol: String; let label: String; let action: () -> Void
    public init(_ symbol: String, label: String, action: @escaping () -> Void) { self.symbol = symbol; self.label = label; self.action = action }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .rmIconButton().accessibilityLabel(label)
    }
}
