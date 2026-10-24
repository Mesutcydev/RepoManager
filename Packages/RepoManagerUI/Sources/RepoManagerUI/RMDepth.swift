import SwiftUI

/// One frosted reading surface. Controls inside stay plain so glass does not
/// accumulate on every row. Accessibility preferences replace blur with a solid fill.
public struct RMFrostedPanelBackground: View {
    private let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale
    public init(cornerRadius: CGFloat = RMLayout.cardCorner) { self.cornerRadius = cornerRadius }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency || contrast == .increased { shape.fill(RMPalette.surface) }
            else { shape.fill(.thinMaterial) }
            shape.fill(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.065 : 0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.3 : 0.85), RMPalette.line.opacity(contrast == .increased ? 1 : 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: contrast == .increased ? 1 : RMLayout.hairline(displayScale: displayScale))
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.055), radius: 14, y: 6)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Solid, legible surfaces with a light-catching edge and a quiet cast shadow.
/// Lighting is static: it adds depth without a rendering timer or moving canvas.
public struct RMPanelBackground: View {
    private let cornerRadius: CGFloat
    private let emphasized: Bool
    private let fill: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    public init(cornerRadius: CGFloat = RMLayout.cardCorner, emphasized: Bool = false, fill: Color = RMPalette.surface) {
        self.cornerRadius = cornerRadius; self.emphasized = emphasized; self.fill = fill
    }
    public var body: some View {
        let shape = RoundedRectangle(cornerRadius:cornerRadius,style:.continuous)
        shape.fill(fill)
            .overlay {
                shape.fill(LinearGradient(colors:[.white.opacity(scheme == .dark ? 0.055 : 0.55),.clear,.black.opacity(scheme == .dark ? 0.075 : 0.018)],startPoint:.topLeading,endPoint:.bottomTrailing))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors:[emphasized ? RMPalette.accent.opacity(0.65) : .white.opacity(scheme == .dark ? 0.19 : 0.95),RMPalette.line.opacity(contrast == .increased ? 1 : 0.5)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:contrast == .increased ? 1 : RMLayout.hairline(displayScale:displayScale))
            }
            .shadow(color:.black.opacity(scheme == .dark ? 0.22 : 0.07),radius:12,y:7)
            .shadow(color:.black.opacity(scheme == .dark ? 0.12 : 0.025),radius:2,y:1)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Immediate touch-down response, followed by an interruptible spring release.
struct RMControlPressFeedback: ViewModifier {
    let pressed: Bool
    @Environment(\.rmMotionIsReduced) private var reduced
    func body(content: Content) -> some View {
        content.opacity(pressed ? 0.86 : 1)
            .scaleEffect(pressed && !reduced ? 0.975 : 1)
            .animation(pressed || reduced ? nil : .spring(response:0.28,dampingFraction:0.86),value:pressed)
    }
}
