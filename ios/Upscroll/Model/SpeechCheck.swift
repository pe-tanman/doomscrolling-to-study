import Foundation
import Speech
import AVFoundation

/// "Say it": listen in Japanese (on-device when available) and check the phrase was said.
/// Transcripts can come back in kanji or kana, so both sides are compared as romaji.
@MainActor
final class SpeechCheck: ObservableObject {
    enum State: Equatable { case idle, listening, heard(String, Bool), denied, unavailable }
    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    /// The learner said another right word for the same meaning (かんたん for "easy" when the card's word is やさしい).
    @Published private(set) var heardAlternative: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    /// A new engine for every attempt: the input format has to be read after the session switched to recording,
    /// and a reused engine can hold the old (playback-only) format.
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var target = ""
    private var alternatives: [String] = []
    private var stopTimer: Task<Void, Never>?

    /// Speech recognition or the microphone was refused: don't keep offering speaking tasks.
    nonisolated static var permissionDenied: Bool {
        let s = SFSpeechRecognizer.authorizationStatus()
        return s == .denied || s == .restricted || AVAudioApplication.shared.recordPermission == .denied
    }

    /// `alternatives`: other words for the same meaning, also accepted as right.
    func start(target: String, alternatives: [String] = []) async {
        self.target = target
        self.alternatives = alternatives.filter { $0 != target }
        heardAlternative = nil
        guard let recognizer, recognizer.isAvailable else { state = .unavailable; return }
        let speechOK = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        let micOK = await AVAudioApplication.requestRecordPermission()
        guard speechOK, micOK else { state = .denied; return }

        stop()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            state = .unavailable; return   // the mic can't be opened now (another app has it, no input device…)
        }
        guard session.isInputAvailable else { state = .unavailable; stop(); return }
        engine = AVAudioEngine()
        let input = engine.inputNode
        // No usable microphone format (0 Hz / 0 channels: simulator without a mic, input busy, route changing).
        // Installing a tap with it raises an Objective-C exception that Swift can't catch, so check first.
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { state = .unavailable; stop(); return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
            req.append(buf)
            let ch = buf.floatChannelData?[0]
            var peak: Float = 0
            if let ch { for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[i])) } }
            Task { @MainActor in self?.level = min(1, peak * 3) }
        }
        do { try engine.start() } catch { state = .unavailable; stop(); return }
        state = .listening
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    var ok = Self.matches(text, target: self.target)
                    if !ok, let alt = self.alternatives.first(where: { Self.matches(text, target: $0) }) {
                        ok = true
                        self.heardAlternative = alt
                    } else if ok {
                        self.heardAlternative = nil
                    }
                    self.state = .heard(text, ok)
                    if ok || result?.isFinal == true { self.stop() }
                }
                if error != nil { self.stop() }
            }
        }
        stopTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            self?.stop()
        }
    }

    func stop() {
        stopTimer?.cancel()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        level = 0
        if state == .listening { state = .idle }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    /// Romaji of any Japanese text (kanji, kana or mixed), letters only.
    nonisolated static func romaji(_ text: String) -> String {
        let s = text as NSString
        let tok = CFStringTokenizerCreate(nil, s, CFRange(location: 0, length: s.length), kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
        var out = ""
        var t = CFStringTokenizerAdvanceToNextToken(tok)
        while !t.isEmpty {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tok, kCFStringTokenizerAttributeLatinTranscription) as? String {
                out += latin
            } else {
                let r = CFStringTokenizerGetCurrentTokenRange(tok)
                out += s.substring(with: NSRange(location: r.location, length: r.length))
            }
            t = CFStringTokenizerAdvanceToNextToken(tok)
        }
        return out.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter && $0.isASCII }
    }

    /// Said it if the romaji is close enough (≥ 75% similar) or contains the target.
    nonisolated static func matches(_ heard: String, target: String) -> Bool {
        let a = romaji(heard), b = romaji(target)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.contains(b) { return true }
        return similarity(a, b) >= 0.75
    }

    nonisolated static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for i in 1...max(1, x.count) where !x.isEmpty {
            var cur = [i] + Array(repeating: 0, count: y.count)
            for j in 1...max(1, y.count) where !y.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        let d = Double(prev[y.count])
        return 1 - d / Double(max(x.count, y.count))
    }
}
