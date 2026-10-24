import SwiftUI
#if canImport(UIKit)
import UIKit
import Observation

/// Each workspace has its own safe-area and accessibility root. Keep its hosting
/// root fixed: replacing it for every observed draft edit interrupts native input.
struct RMMountedWorkspace: UIViewControllerRepresentable {
    let content: AnyView; let visible: Bool; let interactive: Bool
    @Environment(\.rmAppearance) private var appearance
    @Environment(\.layoutDirection) private var direction
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.rmMotionIsReduced) private var reduced
    func makeUIViewController(context:Context) -> RetainedWorkspaceController {
        RetainedWorkspaceController(content:content,state:RetainedWorkspaceState(visible:visible,interactive:interactive,appearance:appearance,direction:direction,locale:locale,typeSize:typeSize,reduced:reduced))
    }
    func updateUIViewController(_ controller:RetainedWorkspaceController,context:Context) {
        controller.state.visible = visible; controller.state.interactive = interactive; controller.state.appearance = appearance
        controller.state.direction = direction; controller.state.locale = locale; controller.state.typeSize = typeSize
        controller.state.reduced = reduced; controller.applyVisibility()
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiViewController:RetainedWorkspaceController,context:Context) -> CGSize? {
        guard let width = proposal.width,let height = proposal.height,width.isFinite,height.isFinite else { return nil }
        return CGSize(width:width,height:height)
    }
}
@MainActor @Observable final class RetainedWorkspaceState {
    var visible: Bool; var interactive: Bool; var appearance: RMAppearancePreference; var direction: LayoutDirection
    var typeSize: DynamicTypeSize; var reduced: Bool
    var locale: Locale
    init(visible:Bool,interactive:Bool,appearance:RMAppearancePreference,direction:LayoutDirection,locale:Locale,typeSize:DynamicTypeSize,reduced:Bool) {
        self.visible = visible; self.interactive = interactive; self.appearance = appearance; self.direction = direction
        self.locale = locale; self.typeSize = typeSize; self.reduced = reduced
    }
}
private struct RetainedWorkspaceRoot: View {
    let content: AnyView; let state: RetainedWorkspaceState
    var body: some View {
        content.environment(\.rmWorkspaceVisible,state.visible && state.interactive).environment(\.rmAppearance,state.appearance)
            .environment(\.layoutDirection,state.direction).environment(\.dynamicTypeSize,state.typeSize)
            .environment(\.locale,state.locale)
            .accessibilityHidden(!state.visible || !state.interactive).allowsHitTesting(state.visible && state.interactive)
    }
}
@MainActor final class RetainedWorkspaceController: UIViewController {
    let state: RetainedWorkspaceState
    private let host: UIHostingController<RetainedWorkspaceRoot>
    private let viewport = UIView()
    private var passiveSnapshot: UIView?
    init(content:AnyView,state:RetainedWorkspaceState) {
        self.state = state; host = UIHostingController(rootView:RetainedWorkspaceRoot(content:content,state:state))
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .clear; view.clipsToBounds = true; viewport.backgroundColor = .clear; viewport.clipsToBounds = true
        view.addSubview(viewport); viewport.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([viewport.leadingAnchor.constraint(equalTo:view.leadingAnchor),viewport.trailingAnchor.constraint(equalTo:view.trailingAnchor),viewport.topAnchor.constraint(equalTo:view.topAnchor),viewport.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        host.sizingOptions = []
        host.view.translatesAutoresizingMaskIntoConstraints = false; host.view.backgroundColor = .clear; host.view.clipsToBounds = true
        applyVisibility()
    }
    func applyVisibility() {
        guard isViewLoaded else { return }
        let interactive = state.visible && state.interactive
        if !interactive { viewport.endEditing(true) }
        // UIKit-hosted SwiftUI can publish virtual AX nodes and intercept hits
        // even when SwiftUI's outer modifiers hide it. Detach the native host
        // behind a modal drawer, retaining its state and an in-memory backdrop.
        // The backdrop has no controls, accessibility or persistent file.
        if state.visible,!interactive,host.parent != nil,passiveSnapshot == nil,
           let snapshot = host.view.snapshotView(afterScreenUpdates:false) {
            snapshot.isUserInteractionEnabled = false; snapshot.accessibilityElementsHidden = true
            snapshot.translatesAutoresizingMaskIntoConstraints = false
            viewport.addSubview(snapshot)
            NSLayoutConstraint.activate([snapshot.leadingAnchor.constraint(equalTo:viewport.leadingAnchor),snapshot.trailingAnchor.constraint(equalTo:viewport.trailingAnchor),snapshot.topAnchor.constraint(equalTo:viewport.topAnchor),snapshot.bottomAnchor.constraint(equalTo:viewport.bottomAnchor)])
            passiveSnapshot = snapshot
        }
        if interactive || !state.visible { passiveSnapshot?.removeFromSuperview(); passiveSnapshot = nil }
        if interactive,host.parent == nil {
            addChild(host); viewport.addSubview(host.view)
            NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo:viewport.leadingAnchor),host.view.trailingAnchor.constraint(equalTo:viewport.trailingAnchor),host.view.topAnchor.constraint(equalTo:viewport.topAnchor),host.view.bottomAnchor.constraint(equalTo:viewport.bottomAnchor)])
            host.didMove(toParent:self)
        } else if !interactive,host.parent != nil {
            host.willMove(toParent:nil); host.view.removeFromSuperview(); host.removeFromParent()
        }
        view.isHidden = !state.visible
        view.isUserInteractionEnabled = interactive
        view.accessibilityElementsHidden = !interactive
        host.view.accessibilityElementsHidden = !interactive
        viewport.isHidden = !state.visible; viewport.isUserInteractionEnabled = interactive
        viewport.accessibilityElementsHidden = !interactive
    }
}
#else
struct RMMountedWorkspace: View {
    let content: AnyView; let visible: Bool; let interactive: Bool
    var body: some View { content.environment(\.rmWorkspaceVisible,visible && interactive).opacity(visible ? 1 : 0).allowsHitTesting(visible && interactive).accessibilityHidden(!visible || !interactive) }
}
#endif
