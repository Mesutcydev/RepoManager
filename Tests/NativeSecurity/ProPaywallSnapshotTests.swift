import XCTest
import SwiftUI
import UIKit
import RepoManagerUI
@testable import RepoManager

final class ProPaywallSnapshotTests: XCTestCase {
    @MainActor func testPaywallPreviewRendersWithFreeChatGPTAndOneTimePrice() async throws {
        guard DevelopmentFixtures.pro else { throw XCTSkip("Run the ProPaywallPreview scheme with isolated UI fixtures.") }
        let store = ProStore(enabled:true); store.start(); await store.loadProduct()
        XCTAssertEqual(store.price,"$9.99"); XCTAssertTrue(store.canPurchase)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController
        let controller = UIHostingController(rootView:AnyView(EmptyView()))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.rootViewController = original }
        let variants: [(String,ColorScheme,DynamicTypeSize,LayoutDirection)] = [
            ("Dark",.dark,.large,.leftToRight),
            ("Light",.light,.large,.leftToRight),
            ("Large text RTL",.dark,.accessibility3,.rightToLeft)
        ]
        for (name,scheme,size,direction) in variants {
            controller.rootView = AnyView(ProUnlockView(store:store)
                .preferredColorScheme(scheme).environment(\.dynamicTypeSize,size)
                .environment(\.layoutDirection,direction))
            controller.view.layoutIfNeeded()
            try await Task.sleep(for:.seconds(2))
            let format = UIGraphicsImageRendererFormat(); format.scale = window.screen.scale
            let image = UIGraphicsImageRenderer(bounds:window.bounds,format:format).image { _ in
                window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)
            }
            let attachment = XCTAttachment(image:image)
            attachment.name = "Premium Pro paywall — \(name)"; attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
