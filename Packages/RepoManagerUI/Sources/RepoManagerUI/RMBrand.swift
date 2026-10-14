import SwiftUI

/// The repository case is the sole brand symbol. Git branch glyphs identify Git operations only.
public enum RMBrand {
    public static let canvas = Color(red:17/255,green:19/255,blue:21/255)
    public static let ceramic = Color(red:245/255,green:242/255,blue:235/255)
    public static let emerald = Color(red:103/255,green:212/255,blue:161/255)
}

public struct RMWordmark: View {
    public init() {}
    public var body: some View {
        Text("Repo Manager").font(.system(.title3,design:.default).weight(.semibold)).tracking(-0.45)
    }
}

/// A cold-launch entrance. It never repeats during navigation, voice, or scene activation.
/// The opaque OS launch canvas matches this view; animated layers run only inside the app.
public struct RMSplashScreen: View {
    private let ready: Bool
    private let finish: () -> Void
    @Environment(\.rmMotionIsReduced) private var systemReduced
    private let reduceMotionOverride: Bool
    private var reduced: Bool { systemReduced || reduceMotionOverride }
    @State private var entered = false
    @State private var settled = false
    @State private var artworkSettled = false
    @State private var illuminated = false
    @State private var named = false
    @State private var sequenceComplete = false
    @State private var delivered = false
    @State private var leaving = false
    public init(ready:Bool,reduceMotion:Bool = false,finish:@escaping () -> Void) { self.ready = ready; reduceMotionOverride = reduceMotion; self.finish = finish }
    public var body: some View {
        GeometryReader { geometry in
            let size = min(280,max(176,geometry.size.width*0.58))
            VStack(spacing:12) {
                ZStack {
                    if reduced || artworkSettled {
                        Image("RMLogo",bundle:.module).resizable().scaledToFit()
                    } else {
                        Image("RMLogo",bundle:.module).resizable().scaledToFit()
                            .mask { Rectangle().overlay { FileCardsMask().blendMode(.destinationOut) }.compositingGroup() }
                        Image("RMLogo",bundle:.module).resizable().scaledToFit().mask(FileCardsMask())
                            .offset(y:settled ? 0 : -8)
                    }
                    RoundedRectangle(cornerRadius:size*0.035)
                        .fill(RMBrand.emerald).frame(width:size*0.15,height:size*0.018)
                        .position(x:size*0.5,y:size*0.595).opacity(illuminated && !reduced ? 0.35 : 0)
                        .blendMode(.plusLighter)
                }.frame(width:size,height:size).compositingGroup().accessibilityHidden(true)
                    .scaleEffect(reduced || entered ? 1 : 0.97)
                    .offset(y:reduced || entered ? 0 : 8)
                    .opacity(entered ? 1 : 0)
                RMWordmark().foregroundStyle(RMBrand.ceramic).opacity(named ? 1 : 0).accessibilityHidden(true)
                    .offset(y:reduced || named ? 0 : 4)
                if sequenceComplete && !ready {
                    Text("Opening your workspace…").font(.caption).foregroundStyle(RMBrand.ceramic.opacity(0.6))
                        .transition(.opacity)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).offset(y:-20).opacity(leaving ? 0 : 1)
        }.background(RMBrand.canvas.ignoresSafeArea()).colorScheme(.dark)
            .accessibilityElement(children:.ignore).accessibilityLabel("Repo Manager is opening your encrypted workspace")
            .accessibilityIdentifier("launch.brand")
            .task { await enter() }
            .task(id:ready && sequenceComplete) { await leaveIfReady() }
    }
    @MainActor private func enter() async {
        do {
            withAnimation(.easeOut(duration:reduced ? 0.16 : 0.22)) { entered = true }
            try await Task.sleep(for:.milliseconds(120)); try Task.checkCancellation()
            if reduced { settled = true; artworkSettled = true }
            else {
                withAnimation(.spring(duration:0.38,bounce:0.04),completionCriteria:.logicallyComplete) {
                    settled = true
                } completion: { artworkSettled = true }
            }
            try await Task.sleep(for:.milliseconds(220)); try Task.checkCancellation()
            withAnimation(.easeOut(duration:0.18)) { illuminated = true; named = true }
            try await Task.sleep(for:.milliseconds(reduced ? 140 : 300)); try Task.checkCancellation()
            withAnimation(.easeOut(duration:0.16)) { illuminated = false }
            try await Task.sleep(for:.milliseconds(160)); try Task.checkCancellation()
            sequenceComplete = true
        } catch { /* The view owns its short animation task; cancellation never starts work. */ }
    }
    @MainActor private func leaveIfReady() async {
        guard ready,sequenceComplete,!delivered else { return }; delivered = true
        do {
            withAnimation(.easeOut(duration:0.12)) { leaving = true }
            try await Task.sleep(for:.milliseconds(150)); try Task.checkCancellation()
            finish()
        } catch { delivered = false; leaving = false }
    }
}

/// Fixed artwork-space mask for the approved 1280px transparent repository-case master.
/// Both layers sample the same image, so the settled silhouette is pixel-aligned.
private struct FileCardsMask: Shape {
    func path(in rect:CGRect) -> Path {
        var p = Path()
        func v(_ x:CGFloat,_ y:CGFloat) -> CGPoint { CGPoint(x:rect.minX+rect.width*x,y:rect.minY+rect.height*y) }
        p.move(to:v(0.202,0.27))
        p.addLine(to:v(0.202,0.217)); p.addQuadCurve(to:v(0.246,0.164),control:v(0.202,0.164))
        p.addLine(to:v(0.746,0.164)); p.addQuadCurve(to:v(0.794,0.218),control:v(0.794,0.164))
        p.addLine(to:v(0.794,0.285)); p.addQuadCurve(to:v(0.806,0.318),control:v(0.806,0.290))
        p.addLine(to:v(0.806,0.363)); p.addQuadCurve(to:v(0.817,0.399),control:v(0.817,0.377))
        p.addLine(to:v(0.817,0.451)); p.addQuadCurve(to:v(0.184,0.451),control:v(0.5,0.472))
        p.addLine(to:v(0.184,0.395)); p.addQuadCurve(to:v(0.192,0.343),control:v(0.184,0.365))
        p.addLine(to:v(0.192,0.319)); p.addQuadCurve(to:v(0.202,0.27),control:v(0.192,0.287)); p.closeSubpath()
        return p
    }
}
