import SwiftUI
import RepoManagerUI

struct ProUnlockView: View {
    @Bindable var store: ProStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    RMPageHeading("Repo Manager Pro",detail:"Use API providers with your own keys.") { EmptyView() }
                    ProIncludedFeatures()
                    ProPaidFeatures()
                }.padding(RMLayout.pageInset).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
            }.background(RMPageBackground()).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge:.bottom) {
                    ProPurchaseControls(store:store,continueAction:{ dismiss() })
                        .padding(RMLayout.pageInset).frame(maxWidth:620,alignment:.leading).frame(maxWidth:.infinity)
                        .background(.regularMaterial)
                }
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("pro.done") } }
        }.task { await store.loadProduct() }
    }
}
private struct ProIncludedFeatures: View {
    var body: some View {
        RMCard("Included") {
            ProFeatureRow(title:"ChatGPT connection",detail:"Uses your eligible ChatGPT plan and its usage limits.",symbol:"person.crop.circle")
            ProFeatureRow(title:"Apple Intelligence",detail:"Available on supported devices, with no app unlock.",symbol:"apple.intelligence")
            ProFeatureRow(title:"Your GitHub workspace",detail:"Browse repositories, chat and review changes.",symbol:"folder")
        }
    }
}
private struct ProPaidFeatures: View {
    var body: some View {
        RMCard("One-time Pro unlock") {
            ProFeatureRow(title:"API providers",detail:"OpenAI API, Anthropic, Gemini and other supported APIs.",symbol:"key.horizontal")
            ProFeatureRow(title:"Custom HTTPS endpoints",detail:"Connect a compatible endpoint with your own credentials.",symbol:"network")
            Text("Pro unlocks app features. Your provider bills API usage separately; no API credits or ChatGPT subscription are included.")
                .font(RMType.meta).foregroundStyle(RMPalette.secondary).padding(RMLayout.cardInset)
        }
    }
}
private struct ProFeatureRow: View {
    let title: LocalizedStringKey; let detail: LocalizedStringKey; let symbol: String
    var body: some View {
        HStack(alignment:.top,spacing:RMLayout.rowGap) {
            Image(systemName:symbol).foregroundStyle(RMPalette.accentText).frame(width:28).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(RMType.body.weight(.medium))
                Text(detail).font(RMType.meta).foregroundStyle(RMPalette.secondary)
            }
            Spacer(minLength:0)
        }.padding(RMLayout.cardInset)
    }
}
private struct ProPurchaseControls: View {
    @Bindable var store: ProStore
    let continueAction: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:RMLayout.rowGap) {
            if store.unlocked {
                Label("Pro unlocked",systemImage:"checkmark.seal.fill").foregroundStyle(RMPalette.accentText).accessibilityIdentifier("pro.unlocked")
                Button("Continue",action:continueAction).rmProminentButton().accessibilityIdentifier("pro.continue")
            } else {
                if let price = store.price { Text("\(price) once").font(RMType.title).accessibilityIdentifier("pro.price") }
                if store.loading { ProgressView("Loading App Store price…") }
                Button { Task { await store.purchase() } } label: {
                    if store.busy { ProgressView().tint(.black) }
                    else { Text("Unlock Pro") }
                }.rmProminentButton().disabled(!store.canPurchase).accessibilityIdentifier("pro.purchase")
                Text("One purchase. No app subscription.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
            }
            Button("Restore Purchases") { Task { await store.restore() } }.rmSecondaryButton().disabled(store.busy || store.loading).accessibilityIdentifier("pro.restore")
            if !store.unlocked && !store.loading && store.price == nil {
                Button("Retry price lookup") { Task { await store.loadProduct() } }.rmSecondaryButton()
            }
            if let message = store.message { Text(message).font(RMType.meta).foregroundStyle(RMPalette.secondary).accessibilityIdentifier("pro.message") }
            if DevelopmentFixtures.pro { Text("Development preview — no payment is taken.").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
        }
    }
}
