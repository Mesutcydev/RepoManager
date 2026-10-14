// Adapted from OnDeviceMax; see Docs/PROVENANCE.json and LICENSE.
import SwiftUI

/// Semantic colors live in DesignAssets.xcassets, including complete dark variants.
public enum RMPalette {
    public static let background = Color("RMBackground", bundle: .module)
    public static let surface = Color("RMSurface", bundle: .module)
    public static let chrome = Color("RMChrome", bundle: .module)
    public static let input = Color("RMInput", bundle: .module)
    public static let selected = Color("RMSelected", bundle: .module)
    public static let text = Color("RMText", bundle: .module)
    public static let secondary = Color("RMSecondary", bundle: .module)
    public static let line = Color("RMLine", bundle: .module)
    public static let accent = Color("RMAccent", bundle: .module)
    public static let accentText = Color("RMAccentText", bundle: .module)
    public static let accentSoft = Color("RMAccentSoft", bundle: .module)
    public static let send = Color("RMSend", bundle: .module)
    public static let onSend = Color("RMOnSend", bundle: .module)
    public static let graphite = Color("RMGraphite", bundle: .module)
    public static let ivory = Color("RMIvory", bundle: .module)
    public static let red = Color("RMRed", bundle: .module)
}

/// One geometry system on a 4-pt grid. Every metric is a multiple of `unit`,
/// and nested corners are concentric: inner radius + inset = outer radius.
public enum RMLayout {
    public static let unit: CGFloat = 4

    // Spacing scale: 1u 2u 3u 4u 5u 6u.
    public static let elementGap = 2 * unit            // 8, inside a group
    public static let rowGap = 3 * unit                // 12, tile to text
    public static let cardInset = 4 * unit             // 16, card padding
    public static let pageInset = 5 * unit             // 20, screen margins
    public static let groupGap = 6 * unit              // 24, between groups

    // Controls: three heights. Every control is a capsule or circle (radius = height / 2).
    public static let controlCompact = 9 * unit        // 36: chips, segmented, send
    public static let minimumHit = 11 * unit           // 44: icon buttons, the minimum target
    public static let controlLarge = 13 * unit         // 52: primary and secondary actions

    // Rows: a tile inset by the card padding fixes the card corner and the row height.
    public static let tile = 8 * unit                  // 32
    public static let tileCorner = tile / 4            // 8
    public static let cardCorner = tileCorner + cardInset   // 24, concentric with the tile
    public static let rowHeight = tile + 2 * cardInset      // 64
    public static let dividerInset = cardInset + tile + rowGap   // 60, where row text starts
    /// Standalone blocks (drawer tiles, highlighted rows) share the tile's 1:4 corner ratio.
    public static let rowCorner = rowHeight / 4        // 16
    public static let heroTile = 12 * unit             // 48, empty states and headers
    /// A one-line user bubble is 46 pt tall; 20 keeps it a soft pill that stays
    /// rectangular, not a capsule, as it grows to more lines.
    public static let bubbleCorner = 5 * unit

    /// Glyphs stop growing here, so they stay inside 44-pt targets at accessibility sizes.
    public static let glyphMaximum = 7 * unit
    public static let standardIcon = 5 * unit
    /// A 20-pt glyph centered in a 44-pt target sits 12 pt in from the target's edge.
    /// Trailing inline icons pull out by this much so glyphs align with chevrons.
    public static let inlineIconOutset = (minimumHit - standardIcon) / 2

    // Composer: text on a 20-pt inset level with the leading icon, a row of 44-pt
    // targets, and a 36-pt send circle concentric with the corner (30 = 18 + 12).
    public static let composerSideInset = 2 * unit
    public static let composerTopInset = 4 * unit
    public static let composerFooterGap = 2 * unit
    public static let composerBottomInset = 2 * unit
    public static let composerSendDiameter = controlCompact
    public static let composerGlyphMaximum = glyphMaximum
    public static let composerAttachmentGap = unit
    public static let composerInputStackGap = unit
    public static let composerMinimumHeight = composerTopInset + composerFooterGap + minimumHit + composerBottomInset
    public static let composerCorner = composerSendDiameter / 2 + 3 * unit
    public static let composerMicPrimaryGap = 2 * unit
    /// Added to `composerSideInset` so the writing text starts 20 pt in.
    public static let textAdditionalHorizontalInset = 3 * unit

    public static let userBubbleWidthFraction: CGFloat = 0.82
    public static let drawerWidthFraction: CGFloat = 0.775
    public static let drawerMaximumWidth = 90 * unit

    public static func floorPixel(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (max(value, 0) * scale).rounded(.down) / scale
    }
    public static func maxUserBubbleWidth(contentWidth: CGFloat, displayScale: CGFloat) -> CGFloat {
        floorPixel(contentWidth * userBubbleWidthFraction, displayScale: displayScale)
    }
    public static func hairline(displayScale: CGFloat) -> CGFloat { 1 / max(displayScale, 1) }
    public static func drawerWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, min(availableWidth * drawerWidthFraction, drawerMaximumWidth))
    }
}

/// Seven type roles on five sizes of Apple's Dynamic Type ramp (34 · 20 · 17 · 15 · 13
/// at the default size), so every role scales together. Weight separates roles of one size.
public enum RMType {
    public static let pageTitle = Font.largeTitle.weight(.bold)      // 34, one per screen
    public static let title = Font.title3.weight(.semibold)          // 20, card and sheet heroes
    public static let rowTitle = Font.body.weight(.semibold)         // 17, the name in a row
    public static let body = Font.body                               // 17, reading text
    public static let detail = Font.subheadline                      // 15, secondary line
    public static let label = Font.footnote.weight(.semibold)        // 13, section headers, chips
    public static let meta = Font.footnote                           // 13, footers, timestamps, counts
}

/// A native preference; storage is configurable on RMStore.
public enum RMAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark, oled
    public var id: String { rawValue }
    public var title: String { self == .oled ? "OLED" : rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .oled: return "moon.fill"
        }
    }
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .oled: return .dark
        }
    }
}

private struct RMAppearanceKey: EnvironmentKey {
    static let defaultValue: RMAppearancePreference = .system
}

extension EnvironmentValues {
    @Entry public var rmReduceMotionOverride: Bool = false
    public var rmMotionIsReduced: Bool { accessibilityReduceMotion || rmReduceMotionOverride }
    public var rmAppearance: RMAppearancePreference {
        get { self[RMAppearanceKey.self] }
        set { self[RMAppearanceKey.self] = newValue }
    }
}

/// The page canvas is distinct from raised surfaces, especially in OLED mode.
public struct RMPageBackground: View {
    @Environment(\.rmAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        // View backgrounds stop at the safe area; without this, bars over the page show the black window.
        ZStack {
            appearance == .oled ? Color.black : RMPalette.background
            if appearance != .oled {
                RadialGradient(colors:[RMPalette.accent.opacity(scheme == .dark ? 0.065 : 0.035),.clear],center:.topTrailing,startRadius:0,endRadius:460)
                LinearGradient(colors:[.white.opacity(scheme == .dark ? 0.025 : 0.16),.clear],startPoint:.topLeading,endPoint:.bottom)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
