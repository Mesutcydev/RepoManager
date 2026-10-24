import Foundation
import Observation
import StoreKit
import RepoManagerCore

enum AppProConfiguration {
    static var productID: String {
        Bundle.main.object(forInfoDictionaryKey:"RepoManagerProProductID") as? String ?? ""
    }
    static var enabled: Bool {
        if DevelopmentFixtures.pro { return true }
        return (Bundle.main.object(forInfoDictionaryKey:"RepoManagerProAPIProvidersEnabled") as? String)?.uppercased() == "YES"
    }
}

@MainActor @Observable final class ProStore {
    let enabled: Bool
    let access: ProviderAccessGate
    private(set) var unlocked = false
    private(set) var loading = false
    private(set) var busy = false
    private(set) var purchasePending = false
    private(set) var price: String?
    private(set) var message: String?
    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var updates: Task<Void,Never>?
    @ObservationIgnored private var entitlementEpoch: UInt64 = 0
    @ObservationIgnored private var fixtureOwned = false

    init(enabled: Bool = AppProConfiguration.enabled) {
        self.enabled = enabled
        access = ProviderAccessGate(enforced:enabled)
    }
    deinit { updates?.cancel() }
    var canPurchase: Bool { enabled && !unlocked && !busy && !loading && !purchasePending && (product != nil || DevelopmentFixtures.pro) }
    func requiresUnlock(_ profile: ProviderProfile) -> Bool { enabled && !unlocked && ProviderAccessPolicy.requiresPro(profile) }

    func start() {
        guard enabled,updates == nil else { return }
        if DevelopmentFixtures.pro {
            fixtureOwned = DevelopmentFixtures.proOwned
            Task { await apply(fixtureOwned) }
            return
        }
        let productID = AppProConfiguration.productID
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self,!Task.isCancelled else { return }
                guard case let .verified(transaction) = result,transaction.productID == productID,
                      transaction.productType == .nonConsumable else { continue }
                if transaction.revocationDate == nil {
                    // A verified approval is authoritative before StoreKit's
                    // entitlement snapshot has necessarily caught up.
                    self.entitlementEpoch &+= 1
                    await self.apply(true)
                } else {
                    await self.refreshEntitlements()
                }
                await transaction.finish()
            }
        }
        Task { await refreshEntitlements() }
    }
    func loadProduct() async {
        guard enabled,!loading else { return }
        loading = true; product = nil; price = nil; message = nil
        defer { loading = false }
        await refreshEntitlements()
        if DevelopmentFixtures.pro { price = "$9.99"; return }
        do {
            let products = try await Product.products(for:[AppProConfiguration.productID])
            product = products.first { $0.id == AppProConfiguration.productID && $0.type == .nonConsumable }
            price = product?.displayPrice
            if product == nil { message = String(localized:"Pro is not available for purchase in this storefront yet. You can still restore an existing purchase.") }
        } catch { message = String(localized:"Couldn’t load the App Store price. Try again when connected.") }
    }
    func refreshEntitlements() async {
        guard enabled else { return }
        if DevelopmentFixtures.pro { await apply(fixtureOwned); return }
        entitlementEpoch &+= 1; let epoch = entitlementEpoch
        var verified = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard !Task.isCancelled else { return }
            if case let .verified(transaction) = result,
               transaction.productID == AppProConfiguration.productID,
               transaction.productType == .nonConsumable,transaction.revocationDate == nil { verified = true }
        }
        guard !Task.isCancelled,epoch == entitlementEpoch else { return }
        // A complete empty snapshot removes access after a refund/revocation.
        await apply(verified)
    }
    func purchase() async {
        guard canPurchase else { return }
        busy = true; message = nil; defer { busy = false }
        if DevelopmentFixtures.pro { fixtureOwned = true; await apply(true); return }
        guard let product else { return }
        do {
            switch try await product.purchase() {
            case let .success(result):
                guard case let .verified(transaction) = result,transaction.productID == AppProConfiguration.productID,
                      transaction.productType == .nonConsumable,transaction.revocationDate == nil else {
                    message = String(localized:"The App Store purchase could not be verified. Pro has not been unlocked."); return
                }
                entitlementEpoch &+= 1
                await apply(true); await transaction.finish()
            case .pending:
                purchasePending = true
                message = String(localized:"Purchase approval is pending. Pro will unlock when the App Store confirms it.")
            case .userCancelled: break
            @unknown default: message = String(localized:"The App Store returned an unknown purchase state. Try Restore Purchases.")
            }
        } catch {
            if !Self.isPurchaseCancellation(error) {
                message = String(localized:"The purchase couldn’t be completed. You can try again or restore an existing purchase.")
            }
        }
    }
    func restore() async {
        guard enabled,!busy else { return }
        busy = true; message = nil; defer { busy = false }
        if DevelopmentFixtures.pro {
            await apply(fixtureOwned); message = unlocked ? String(localized:"Pro purchase restored.") : String(localized:"No Pro purchase was found."); return
        }
        do {
            try await AppStore.sync(); await refreshEntitlements()
            message = unlocked ? String(localized:"Pro purchase restored.") : String(localized:"No Pro purchase was found for this Apple Account.")
        } catch { message = String(localized:"Couldn’t restore purchases. Check your App Store account and try again.") }
    }
    private func apply(_ value: Bool) async {
        await access.setUnlocked(value); unlocked = value
        if value { purchasePending = false; message = nil }
    }
    private static func isPurchaseCancellation(_ error: any Error, depth: Int = 0) -> Bool {
        guard depth < 4 else { return false }
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .userCancelled: return true
            case .systemError(let underlying): return isPurchaseCancellation(underlying, depth: depth + 1)
            default: break
            }
        }
        let failure = error as NSError
        if failure.domain == SKErrorDomain && failure.code == SKError.paymentCancelled.rawValue { return true }
        if failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError { return true }
        if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? any Error {
            return isPurchaseCancellation(underlying, depth: depth + 1)
        }
        return false
    }
}
