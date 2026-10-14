import SwiftUI
import RepoManagerCore
import RepoManagerUI

struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var page = 0
    @State private var pairing = false
    @State private var providers = false
    @State private var preview = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    private let titles = ["A little closer\nto your code.","Your connections.\nYour choice.","Every change,\nin your hands."]
    private let details = ["A native workspace for your GitHub repositories. Read, discuss, and shape your next change in one place.","Pair GitHub and bring the API provider you trust. You choose the repository, model, and destination for each conversation.","Plan first. Stage when you’re ready. A complete review stands between every draft and GitHub."]
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:RMLayout.rowGap) {
                RMBrandGlyph().frame(width:RMLayout.minimumHit,height:RMLayout.minimumHit)
                Text("Repo Manager").font(RMType.detail.weight(.semibold))
                Spacer()
                Text("\(page+1) of 3").font(RMType.detail).monospacedDigit().foregroundStyle(RMPalette.secondary)
            }.padding(.horizontal,RMLayout.pageInset).padding(.top,RMLayout.cardInset).padding(.bottom,RMLayout.pageInset)
            ScrollView {
                VStack(alignment:.leading,spacing:RMLayout.groupGap) {
                    Text(titles[page]).font(RMType.pageTitle)
                        .fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
                    Text(details[page]).font(RMType.body).foregroundStyle(RMPalette.secondary).lineSpacing(4)
                        .fixedSize(horizontal:false,vertical:true)
                    if page == 0 { RepositoryIllustration() }
                    else if page == 1 { connections }
                    else { review }
                }.padding(.horizontal,RMLayout.pageInset).padding(.top,RMLayout.rowGap).padding(.bottom,RMLayout.groupGap)
                    .frame(maxWidth:600,alignment:.leading).frame(maxWidth:.infinity)
            }.scrollBounceBehavior(.basedOnSize)
            // A safe-area bar gives the footer the native scroll-edge fade instead of a hard cut.
            .safeAreaBar(edge:.bottom) { VStack(spacing:RMLayout.rowGap) {
                HStack(spacing:RMLayout.unit) {
                    Image(systemName:"lock.fill").font(RMType.meta)
                    Text(page == 1 ? "Credentials stay in Keychain." : "Your local workspace stays encrypted.").font(RMType.meta)
                }.foregroundStyle(RMPalette.secondary)
                Button { advance() } label: {
                    HStack { Text(page == 2 ? "Open my workspace" : "Continue"); Spacer(); Image(systemName:"arrow.right") }
                }.rmProminentButton().accessibilityIdentifier("onboarding.continue")
                Button("Back") { change(page-1) }.rmTextButton().accessibilityIdentifier("onboarding.back")
                    .opacity(page > 0 ? 1 : 0).disabled(page == 0).accessibilityHidden(page == 0)
            }.padding(.horizontal,RMLayout.pageInset).padding(.top,RMLayout.rowGap).padding(.bottom,RMLayout.rowGap).frame(maxWidth:600) }
        }.foregroundStyle(RMPalette.text).background(RMPageBackground().ignoresSafeArea())
            .sheet(isPresented:$pairing) { GitHubPairingView(model:model) }
            .sheet(isPresented:$providers) { ProviderPresetChooser(model:model) }

    }
    private var connections: some View {
        RMCard(footer:"You can set these up later. Network requests begin only after you configure and allow a destination.") {
            connection("GitHub",detail:model.data.accounts.isEmpty ? "Pair the repositories you work on." : model.data.accounts.count == 1 ? "1 account connected" : "\(model.data.accounts.count) accounts connected",
                       symbol:"arrow.triangle.branch",done:!model.data.accounts.isEmpty) { pairing = true }
            connection("API provider",detail:model.data.providers.isEmpty ? "Bring a key. Choose your model." : model.data.providers.count == 1 ? "1 provider configured" : "\(model.data.providers.count) providers configured",
                       symbol:"point.3.connected.trianglepath.dotted",done:!model.data.providers.isEmpty) { providers = true }
        }
    }
    private func connection(_ title:String,detail:String,symbol:String,done:Bool,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            RMRow(title,detail:detail,accessory:done ? .selected(true) : .chevron) { RMIconTile(symbol) } trailing: { EmptyView() }
        }.buttonStyle(RMPressButtonStyle()).accessibilityHint(title == "GitHub" ? "Connect GitHub" : "Choose a provider")
    }
    private var review: some View {
        VStack(alignment:.leading,spacing:RMLayout.pageInset) {
            HStack(spacing:RMLayout.rowGap) {
                RMEyebrow("Example")
                Spacer()
                Text(preview ? "Review" : "Draft").font(RMType.meta.weight(.medium)).foregroundStyle(RMPalette.accentText)
            }
            VStack(alignment:.leading,spacing:0) {
                HStack { Image(systemName:"doc.text"); Text("README.md"); Spacer(); Text("+1 −1").foregroundStyle(RMPalette.accentText) }
                    .font(.system(.caption,design:.monospaced)).padding(RMLayout.cardInset)
                Divider()
                Text("− A work in progress.").foregroundStyle(RMPalette.red).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap)
                Text("+ Ready for a closer look.").foregroundStyle(RMPalette.accentText).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,RMLayout.cardInset).padding(.vertical,RMLayout.rowGap).background(RMPalette.accentSoft)
                if preview {
                    HStack(spacing:RMLayout.elementGap) { Image(systemName:"checkmark.shield"); Text("One file. One branch. Your review.") }.font(RMType.meta).padding(RMLayout.cardInset).transition(.opacity)
                }
            }.font(.system(.footnote,design:.monospaced)).rmSurface().clipShape(RoundedRectangle(cornerRadius:RMLayout.cardCorner,style:.continuous))
            Button(preview ? "Return to draft" : "Preview the review") { withAnimation(reduced ? nil : .easeOut(duration:0.2)) { preview.toggle() } }.rmSecondaryButton()
                .accessibilityIdentifier("onboarding.review")
            Text("This example stays here. Real approvals always identify the account, repository, branch, and complete change.").font(RMType.meta).foregroundStyle(RMPalette.secondary).lineSpacing(3)
        }
    }
    private func change(_ value:Int) { withAnimation(reduced ? nil : .easeOut(duration:0.2)) { page = value } }
    private func advance() {
        if page < 2 { change(page+1) }
        else { model.data.preferences.onboardingCompleted = true; model.save(); model.selection = .chats }
    }
}
private struct RepositoryIllustration: View {
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            RMBrandGlyph().frame(height:150).frame(maxWidth:.infinity).padding(.vertical,RMLayout.rowGap)
            HStack(spacing:RMLayout.elementGap) { RMBrandGlyph().frame(width:28,height:28); Text("your-repository").font(.system(.subheadline,design:.monospaced)); Spacer(); Text("main").font(.system(.caption,design:.monospaced)).foregroundStyle(RMPalette.secondary) }.padding(RMLayout.pageInset)
            Divider()
            VStack(alignment:.leading,spacing:RMLayout.cardInset) {
                HStack(spacing:RMLayout.elementGap) { Image(systemName:"folder"); Text("Sources"); Spacer(); Text("12 files").font(RMType.meta).foregroundStyle(RMPalette.secondary) }
                HStack(spacing:RMLayout.elementGap) { Image(systemName:"doc.text"); Text("README.md"); Spacer(); Circle().fill(RMPalette.accent).frame(width:5,height:5) }
                HStack(spacing:RMLayout.elementGap) { Image(systemName:"arrow.triangle.pull"); Text("A thoughtful next step"); Spacer() }
            }.font(RMType.detail).padding(RMLayout.pageInset)
            HStack(spacing:RMLayout.elementGap) { Image(systemName:"checkmark.circle"); Text("Explore, plan, then review") }.font(RMType.label).foregroundStyle(RMPalette.accentText).padding(RMLayout.pageInset).frame(maxWidth:.infinity,alignment:.leading).background(RMPalette.accentSoft)
        }.rmSurface().clipShape(RoundedRectangle(cornerRadius:RMLayout.cardCorner,style:.continuous)).accessibilityElement(children:.combine)
    }
}
