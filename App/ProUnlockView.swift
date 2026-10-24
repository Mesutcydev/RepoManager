import SwiftUI
import RepoManagerUI

struct ProUnlockView: View {
    let store: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RMLayout.pageInset) {
                    ProHero()
                    ProBenefits()
                    ProIncludedFeatures()
                    ProBillingDisclosure()
                    ProPurchaseControls(store: store, continueAction: { dismiss() })
                }
                .padding(RMLayout.pageInset)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(RMPageBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("pro.done")
                }
            }
            .modifier(ProSheetToolbar())
        }
        .presentationDetents([.large])
        .task { await store.loadProduct() }
    }
}

/// A sheet with a single Close control is a documented exception to vertical bars.
private struct ProSheetToolbar: ViewModifier {
    func body(content: Content) -> some View {
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) { content.toolbarVerticalBehavior(.disabled) }
        else { content }
        #else
        content
        #endif
    }
}

private struct ProHero: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .title) private var markSize = 72
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RMLayout.rowGap))
            : AnyLayout(HStackLayout(alignment: .center, spacing: RMLayout.cardInset))
        layout {
            Image("ProMark").resizable().scaledToFit()
                .frame(width: markSize, height: markSize)
                .shadow(color: .black.opacity(scheme == .dark ? 0.24 : 0.12), radius: 8, y: 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RMLayout.elementGap) {
                Text("One-time Pro unlock").font(RMType.label).foregroundStyle(RMPalette.accentText)
                Text("Repo Manager Pro").font(.title2.bold()).tracking(-0.5)
                    .foregroundStyle(RMPalette.text).accessibilityAddTraits(.isHeader)
                Text("Your keys. More possibilities.").font(RMType.detail).foregroundStyle(RMPalette.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProBenefits: View {
    var body: some View {
        VStack(spacing: RMLayout.rowGap) {
            ProFeatureRow(title: "API providers", detail: "OpenAI API, Anthropic, Gemini and other supported APIs.", symbol: "key.horizontal")
            ProFeatureRow(title: "Custom HTTPS endpoints", detail: "Connect a compatible endpoint with your own credentials.", symbol: "network")
        }
        .accessibilityIdentifier("pro.benefits")
    }
}

private struct ProFeatureRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RMLayout.rowGap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: RMLayout.cardInset))
        layout {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(RMPalette.accentText)
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: RMLayout.rowGap, style: .continuous)
                        .fill(RMPalette.accentSoft.opacity(0.65))
                        .overlay {
                            RoundedRectangle(cornerRadius: RMLayout.rowGap, style: .continuous)
                                .strokeBorder(RMPalette.accent.opacity(0.12), lineWidth: 0.5)
                        }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RMLayout.unit) {
                Text(title).font(RMType.rowTitle).foregroundStyle(RMPalette.text)
                Text(detail).font(RMType.meta).foregroundStyle(RMPalette.secondary).lineSpacing(2)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, RMLayout.pageInset)
        .padding(.vertical, RMLayout.cardInset)
        .background(ProCardSurface())
        .accessibilityElement(children: .combine)
    }
}

/// Reading cards use the app's graphite and ivory surfaces, with one quiet rim.
/// Keeping the fill solid also preserves clarity with Reduce Transparency enabled.
private struct ProCardSurface: View {
    var included = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RMLayout.cardCorner, style: .continuous)
        shape.fill(RMPalette.surface)
            .overlay {
                shape.fill(LinearGradient(
                    colors: [included ? RMPalette.accent.opacity(scheme == .dark ? 0.07 : 0.035) : .white.opacity(scheme == .dark ? 0.025 : 0.4), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                shape.strokeBorder(
                    contrast == .increased ? RMPalette.secondary : (included ? RMPalette.accent.opacity(0.24) : RMPalette.line.opacity(0.6)),
                    lineWidth: contrast == .increased ? 1 : RMLayout.hairline(displayScale: displayScale))
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.12 : 0.035), radius: 12, y: 5)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct ProIncludedFeatures: View {
    var body: some View {
        HStack(alignment: .top, spacing: RMLayout.cardInset) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(RMPalette.accentText)
                .frame(width: 32, height: 32)
                .background(RMPalette.accentSoft, in: Circle())
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RMLayout.unit) {
                Text("ChatGPT stays free").font(RMType.rowTitle).foregroundStyle(RMPalette.text)
                Text("ChatGPT, Apple Intelligence and GitHub are included.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RMLayout.pageInset)
        .padding(.vertical, RMLayout.cardInset)
        .background(ProCardSurface(included: true))
        .accessibilityElement(children: .combine).accessibilityIdentifier("pro.chatgptIncluded")
    }
}

private struct ProBillingDisclosure: View {
    var body: some View {
        Text("Pro unlocks app features. Your provider bills API usage separately; no API credits or ChatGPT subscription are included.")
            .font(RMType.meta).foregroundStyle(RMPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProPurchaseControls: View {
    let store: ProStore
    let continueAction: () -> Void
    var body: some View {
        VStack(spacing: RMLayout.elementGap) {
            if store.unlocked {
                Label("Pro unlocked", systemImage: "checkmark.seal.fill")
                    .font(RMType.title).foregroundStyle(RMPalette.accentText).accessibilityIdentifier("pro.unlocked")
                Button("Continue", action: continueAction).rmProminentButton().accessibilityIdentifier("pro.continue")
            } else {
                ProPrice(price: store.price, loading: store.loading)
                Button { Task { await store.purchase() } } label: {
                    HStack(spacing: RMLayout.elementGap) {
                        if store.busy { ProgressView().tint(RMPalette.onSend) }
                        if store.purchasePending { Text("Awaiting approval") }
                        else { Text("Unlock Pro") }
                    }.frame(maxWidth: .infinity)
                }
                .rmProminentButton().disabled(!store.canPurchase).accessibilityIdentifier("pro.purchase")
                if !store.loading && store.price == nil {
                    Button("Retry price lookup") { Task { await store.loadProduct() } }
                        .rmTextButton().disabled(store.busy).accessibilityIdentifier("pro.retry")
                }
            }
            if let message = store.message {
                Text(message).font(RMType.meta).foregroundStyle(RMPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("pro.message")
            }
            ProPurchaseLinks(store: store)
            if DevelopmentFixtures.pro {
                Text("Development preview — no payment is taken.").font(.caption2).foregroundStyle(RMPalette.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }
}

private struct ProPrice: View {
    let price: String?
    let loading: Bool
    var body: some View {
        VStack(spacing: RMLayout.unit) {
            if let price {
                Text("\(price) once").font(.title2.bold()).foregroundStyle(RMPalette.text).accessibilityIdentifier("pro.price")
            } else if loading {
                ProgressView("Loading App Store price…").font(RMType.meta)
            }
            Text("One purchase. No app subscription.").font(RMType.meta).foregroundStyle(RMPalette.secondary)
        }
    }
}

private struct ProPurchaseLinks: View {
    let store: ProStore
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: RMLayout.cardInset) { ProRestoreButton(store: store); ProLegalLinks() }
            VStack(spacing: 0) { ProRestoreButton(store: store); ProLegalLinks() }
        }
    }
}

private struct ProRestoreButton: View {
    let store: ProStore
    var body: some View {
        Button("Restore Purchases") { Task { await store.restore() } }
            .rmTextButton().disabled(store.busy || store.loading).accessibilityIdentifier("pro.restore")
    }
}

private struct ProLegalLinks: View {
    var body: some View {
        HStack(spacing: RMLayout.cardInset) {
            Link("Privacy", destination: URL(string: "https://mesut.uk/apps/repo-manager/privacy")!)
            Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
        .font(RMType.meta).foregroundStyle(RMPalette.secondary).frame(minHeight: RMLayout.minimumHit)
    }
}
