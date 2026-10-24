import XCTest
import StoreKit
import StoreKitTest
import RepoManagerCore
@testable import RepoManager

final class ProStoreKitTests: XCTestCase {
    @MainActor func testFailedPurchaseKeepsAPILockedAndChatGPTFree() async throws {
        let configuration = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"RepoManagerPro",withExtension:"storekit"))
        let session = try SKTestSession(contentsOf:configuration)
        session.resetToDefaultState(); session.disableDialogs = true; session.clearTransactions()
        defer { session.clearTransactions() }
        let store = ProStore(enabled:true); await store.loadProduct()
        // Cancellation is checked on device: this SDK translates its simulated
        // userCancelled error to StoreKitError.unknown (ASDServerError 907).
        try await session.setSimulatedError(.purchase(.purchaseNotAllowed),forAPI:.purchase)
        await store.purchase()
        XCTAssertFalse(store.unlocked); XCTAssertFalse(store.busy)
        XCTAssertTrue(store.canPurchase)
        XCTAssertEqual(store.message,"The purchase couldn’t be completed. You can try again or restore an existing purchase.")
        XCTAssertTrue(store.requiresUnlock(ProviderProfile(preset:.openAI)))
        var chatgpt = ProviderProfile(preset:.openAI); chatgpt.authentication = .chatGPT
        try await store.access.require(chatgpt)
    }

    @MainActor func testPendingApprovalKeepsAPILockedAndChatGPTFree() async throws {
        let configuration = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"RepoManagerPro",withExtension:"storekit"))
        let session = try SKTestSession(contentsOf:configuration)
        session.resetToDefaultState(); session.disableDialogs = true; session.clearTransactions()
        session.askToBuyEnabled = true
        defer { session.clearTransactions() }
        let store = ProStore(enabled:true); store.start(); await store.loadProduct(); await store.purchase()
        XCTAssertFalse(store.unlocked); XCTAssertFalse(store.busy)
        XCTAssertFalse(store.canPurchase,"A pending approval must prevent repeated purchase attempts")
        XCTAssertEqual(store.message,"Purchase approval is pending. Pro will unlock when the App Store confirms it.")
        var chatgpt = ProviderProfile(preset:.openAI); chatgpt.authentication = .chatGPT
        try await store.access.require(chatgpt)
        XCTAssertTrue(store.requiresUnlock(ProviderProfile(preset:.openAI)))
        let pending = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier:pending.identifier)
        let deadline = ContinuousClock.now.advanced(by:.seconds(5))
        while !store.unlocked && ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertTrue(store.unlocked); try await store.access.require(ProviderProfile(preset:.openAI))
    }

    @MainActor func testVerifiedPurchaseRestoreAndRefundControlsOnlyAPIProviders() async throws {
        XCTAssertFalse(DevelopmentFixtures.pro,"This test must exercise StoreKit, not the UI preview.")
        let configuration = try XCTUnwrap(Bundle(for:Self.self).url(forResource:"RepoManagerPro",withExtension:"storekit"))
        let session = try SKTestSession(contentsOf:configuration)
        session.resetToDefaultState(); session.disableDialogs = true; session.clearTransactions()
        defer { session.clearTransactions() }

        let store = ProStore(enabled:true); store.start(); await store.loadProduct()
        let products = try await Product.products(for:[AppProConfiguration.productID])
        let product = try XCTUnwrap(products.first)
        XCTAssertEqual(product.id,"com.mesutcydev.repomanager.pro.apiProviders")
        XCTAssertEqual(product.type,.nonConsumable)
        // The app displays StoreKit's localized string and performs no price arithmetic.
        XCTAssertEqual(product.displayPrice,"$9.99")
        XCTAssertEqual(store.price,product.displayPrice); XCTAssertTrue(store.canPurchase); XCTAssertFalse(store.unlocked)
        let api = ProviderProfile(preset:.openAI)
        var chatgpt = ProviderProfile(preset:.openAI); chatgpt.authentication = .chatGPT
        try await store.access.require(chatgpt); try await store.access.require(ProviderProfile(preset:.apple))
        do { try await store.access.require(api); XCTFail("An unowned API provider must be locked") }
        catch { XCTAssertEqual(error as? RMError,.proRequired) }

        await store.purchase()
        XCTAssertTrue(store.unlocked); XCTAssertNil(store.message); try await store.access.require(api)
        let purchased = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == product.id })

        // Recreate the owner state, then run the user-requested StoreKit sync.
        let restored = ProStore(enabled:true); await restored.restore()
        XCTAssertTrue(restored.unlocked); XCTAssertEqual(restored.message,"Pro purchase restored.")
        try await restored.access.require(api)

        try session.refundTransaction(identifier:purchased.identifier)
        // The running store must react to Transaction.updates without a UI refresh.
        let deadline = ContinuousClock.now.advanced(by:.seconds(5))
        while store.unlocked && ContinuousClock.now < deadline { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(store.unlocked,"A verified StoreKit refund must remove Pro automatically")
        await restored.refreshEntitlements(); XCTAssertFalse(restored.unlocked)
        do { try await restored.access.require(api); XCTFail("Refunded API access must be locked") }
        catch { XCTAssertEqual(error as? RMError,.proRequired) }
        try await restored.access.require(chatgpt); try await restored.access.require(ProviderProfile(preset:.apple))
    }
}
