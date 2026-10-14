import Foundation
import Observation
import AVFoundation
import Speech
import RepoManagerCore

/// A single audio lease owns microphone capture, recognition, and native playback.
@MainActor @Observable final class AppleVoice: NSObject, VoiceService, AVSpeechSynthesizerDelegate {
    private(set) var phase: VoicePhase = .idle
    private(set) var transcript = ""
    private(set) var error: String?
    private(set) var preparing = false
    let events: AsyncStream<VoiceEvent>
    private let output: AsyncStream<VoiceEvent>.Continuation
    @ObservationIgnored private lazy var engine = AVAudioEngine()
    @ObservationIgnored private lazy var synthesizer:AVSpeechSynthesizer = {
        let value = AVSpeechSynthesizer(); value.delegate = self; return value
    }()
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var input: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var resultsTask: Task<Void,Never>?
    @ObservationIgnored private var analysisTask: Task<Void,Never>?
    @ObservationIgnored private var timer: Task<Void,Never>?
    @ObservationIgnored private var playbackTask:Task<Void,Never>?
    @ObservationIgnored private let audioSession = VoiceAudioSessionQueue()
    @ObservationIgnored private var playbackFinished = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var speakingUtterance: ObjectIdentifier?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var finalized = ""
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    override init() {
        let pair = AsyncStream<VoiceEvent>.makeStream(bufferingPolicy:.bufferingNewest(32)); events = pair.stream; output = pair.continuation
        super.init()
        for name in [AVAudioSession.interruptionNotification,AVAudioSession.routeChangeNotification,AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] notification in
                // Setting our own capture/playback category emits a route
                // change too; it must not cancel the session being prepared.
                if name == AVAudioSession.routeChangeNotification,
                   let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   raw == AVAudioSession.RouteChangeReason.categoryChange.rawValue { return }
                if name == AVAudioSession.interruptionNotification,
                   let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                   raw != AVAudioSession.InterruptionType.began.rawValue { return }
                Task { @MainActor in self?.stop(); self?.setPhase(.paused) }
            })
        }
    }
    func dictate(locale: String) async throws {
        stop(); error = nil; transcript = ""; finalized = ""
        let lease = generation
        preparing = true
        defer { if lease == generation { preparing = false; if phase != .listening { stop() } } }
        let mic = await AVAudioApplication.requestRecordPermission()
        // TCC invokes its completion on a background queue. A non-Sendable
        // closure created here inherits MainActor and traps in Swift 6 when
        // the user approves speech permission.
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in c.resume(returning:status == .authorized) }
        }
        guard mic, speech else { throw RMError.forbidden }
        guard lease == generation else { throw RMError.cancelled }
        try Task.checkCancellation()
        try await audioSession.activate(.capture)
        guard lease == generation else { throw RMError.cancelled }
        try Task.checkCancellation()
        let node = engine.inputNode
        try? node.setVoiceProcessingEnabled(true)
        let natural = node.outputFormat(forBus:0)
        guard natural.sampleRate > 0, natural.channelCount > 0 else { throw RMError.unavailable }
        let meter = SilenceMeter()
        let supported = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocale(equivalentTo:Locale(identifier:locale)) : nil
        guard lease == generation else { throw RMError.cancelled }
        if let supported {
            let transcriber = SpeechTranscriber(locale:supported,preset:.progressiveTranscription)
            // Asset downloads are system-managed, explicitly started by the user's voice action.
            if let assets = try await AssetInventory.assetInstallationRequest(supporting:[transcriber]) { try await assets.downloadAndInstall() }
            guard lease == generation, let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:[transcriber],considering:natural) else { throw RMError.unavailable }
            guard lease == generation else { throw RMError.cancelled }; try Task.checkCancellation()
            let analyzer = SpeechAnalyzer(modules:[transcriber]); self.analyzer = analyzer
            let pair = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy:.bufferingNewest(16)); input = pair.continuation
            let pipe = try AudioInputPipe(from:natural,to:target,continuation:pair.continuation,meter:meter)
            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.generation == lease else { return }
                        let value = String(result.text.characters)
                        if result.isFinal { self.finalized += value + " " }
                        self.transcript = self.finalized + (result.isFinal ? "" : value)
                        self.output.yield(.transcript(self.transcript,final:false))
                    }
                } catch { if self?.generation == lease { self?.error = RMError.unavailable.localizedDescription } }
            }
            analysisTask = Task { do { try await analyzer.start(inputSequence:pair.stream) } catch { if self.generation == lease { self.error = RMError.unavailable.localizedDescription; self.stop() } } }
            node.installTap(onBus:0,bufferSize:1024,format:natural) { @Sendable buffer,_ in pipe.append(buffer) }; tapInstalled = true
        } else {
            guard let recognizer = SFSpeechRecognizer(locale:Locale(identifier:locale)), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw RMError.unavailable }
            let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            self.request = request
            let sink = LegacyInputPipe(request:request,meter:meter)
            recognition = recognizer.recognitionTask(with:request) { @Sendable [weak self] result,error in
                let value = result?.bestTranscription.formattedString; let final = result?.isFinal ?? false; let failed = error != nil
                Task { @MainActor in
                    guard let self, self.generation == lease else { return }
                    if let value { self.transcript = value; self.output.yield(.transcript(value,final:false)) }
                    if final { self.finishDictation() }
                    else if failed { self.error = RMError.unavailable.localizedDescription; self.stop() }
                }
            }
            node.installTap(onBus:0,bufferSize:1024,format:natural) { @Sendable buffer,_ in sink.append(buffer) }; tapInstalled = true
        }
        engine.prepare(); try engine.start(); preparing = false; setPhase(.listening)
        timer = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for:.milliseconds(200))
                guard let self, self.generation == lease else { return }
                if meter.shouldEnd || Date().timeIntervalSince(start) > 90 { self.finishDictation(); return }
            }
        }
    }
    func finishDictation() {
        guard phase == .listening || phase == .transcribing else { return }
        setPhase(.transcribing); cleanupCapture(); timer?.cancel(); timer = nil
        let lease = generation; let analyzer = analyzer
        Task {
            if let analyzer { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
            try? await Task.sleep(for:.milliseconds(100))
            guard generation == lease else { return }
            let text = transcript.trimmingCharacters(in:.whitespacesAndNewlines)
            stop(); output.yield(.transcript(text,final:true))
        }
    }
    func speak(_ text: String, voiceID: String?, rate: Float) {
        stop()
        let lease = generation; preparing = true; error = nil
        playbackTask = Task { [weak self] in
            guard let self,self.generation == lease,!Task.isCancelled else { return }
            defer { if self.generation == lease { self.preparing = false; self.playbackTask = nil } }
            do {
                try await self.audioSession.activate(.playback)
                try Task.checkCancellation(); guard self.generation == lease else { return }
                let utterance = AVSpeechUtterance(string:String(text.prefix(50000)))
                utterance.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:))
                utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,max(AVSpeechUtteranceMinimumSpeechRate,rate))
                self.speakingUtterance = ObjectIdentifier(utterance); self.setPhase(.speaking); self.synthesizer.speak(utterance)
            } catch {
                if self.generation == lease { self.stop(); self.error = RMError.unavailable.localizedDescription; self.output.yield(.failure(.unavailable)) }
            }
        }
    }
    func pauseForApproval() { stop(); setPhase(.approval) }
    func stop() {
        generation = UUID(); cleanupCapture(); recognition?.cancel(); recognition = nil; request = nil
        playbackTask?.cancel(); playbackTask = nil; preparing = false; playbackFinished = false
        resultsTask?.cancel(); resultsTask = nil; analysisTask?.cancel(); analysisTask = nil; timer?.cancel(); timer = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }; analyzer = nil
        if speakingUtterance != nil { speakingUtterance = nil; synthesizer.stopSpeaking(at:.immediate) }
        finalized = ""; transcript = ""
        audioSession.deactivate(); setPhase(.idle)
    }
    func consumePlaybackFinished() -> Bool { defer { playbackFinished = false }; return playbackFinished }
    private func cleanupCapture() {
        if tapInstalled { engine.stop(); engine.inputNode.removeTap(onBus:0); tapInstalled = false }
        request?.endAudio(); input?.finish(); input = nil
    }
    private func setPhase(_ value: VoicePhase) { guard phase != value else { return }; phase = value; output.yield(.phase(value)) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in guard self.speakingUtterance == id else { return }; self.speakingUtterance = nil; self.audioSession.deactivate(); self.playbackFinished = true; self.setPhase(.idle) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in guard self.speakingUtterance == id else { return }; self.speakingUtterance = nil; self.audioSession.deactivate(); self.playbackFinished = false; if self.phase == .speaking { self.setPhase(.idle) } }
    }
}

/// AVAudioSession's synchronous configuration/activation can block for a route
/// negotiation. A FIFO queue keeps it off the UI thread and preserves Stop →
/// next activation ordering on iOS 26 as well as 27. `active` is queue-confined.
private final class VoiceAudioSessionQueue:@unchecked Sendable {
    enum Intent:Equatable,Sendable { case capture,playback }
    private let queue = DispatchQueue(label:"com.mesutcydev.repomanager.audio-session",qos:.userInitiated)
    private var active = false
    @MainActor func activate(_ intent:Intent) async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,any Error>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    if intent == .capture { try session.setCategory(.playAndRecord,mode:.voiceChat,options:[.defaultToSpeaker,.allowBluetoothHFP]) }
                    else { try session.setCategory(.playback,mode:.spokenAudio) }
                    try session.setActive(true); self.active = true; continuation.resume()
                } catch { continuation.resume(throwing:error) }
            }
        }
    }
    @MainActor func deactivate() {
        queue.async {
            guard self.active else { return }
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
            self.active = false
        }
    }
}

private final class SilenceMeter: @unchecked Sendable {
    private let lock = NSLock(); private var speech = false; private var lastSpeech = Date(); private var lastLevel = 0.0
    var shouldEnd: Bool { lock.withLock { speech && Date().timeIntervalSince(lastSpeech) > 1.4 } }
    func update(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var energy: Float = 0; for i in 0..<Int(buffer.frameLength) { energy += samples[i]*samples[i] }
        let level = Double(sqrt(energy/Float(buffer.frameLength)))
        lock.withLock { lastLevel = level; if level > 0.015 { speech = true; lastSpeech = Date() } }
    }
}
private final class LegacyInputPipe: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest; private let meter: SilenceMeter
    init(request: SFSpeechAudioBufferRecognitionRequest, meter: SilenceMeter) { self.request = request; self.meter = meter }
    func append(_ buffer: AVAudioPCMBuffer) { meter.update(buffer); request.append(buffer) }
}
private final class AudioInputPipe: @unchecked Sendable {
    private let converter: AVAudioConverter; private let target: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation; private let meter: SilenceMeter
    init(from: AVAudioFormat, to: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation, meter: SilenceMeter) throws {
        guard let converter = AVAudioConverter(from:from,to:to) else { throw RMError.unavailable }
        self.converter = converter; target = to; self.continuation = continuation; self.meter = meter
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        meter.update(buffer)
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength)*target.sampleRate/buffer.format.sampleRate)+32)
        guard let output = AVAudioPCMBuffer(pcmFormat:target,frameCapacity:capacity) else { return }
        var supplied = false; var error: NSError?
        let result = converter.convert(to:output,error:&error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }; supplied = true; status.pointee = .haveData; return buffer
        }
        if error == nil && result != .error && output.frameLength > 0 { continuation.yield(AnalyzerInput(buffer:output)) }
    }
}
