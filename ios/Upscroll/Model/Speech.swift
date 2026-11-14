import AVFoundation
import CryptoKit

/// Japanese pronunciation. Natural voice from Gemini 3.8 Flash TTS (through the lesson server, which keeps the key),
/// cached on the device so each word or phrase is fetched once. Falls back to the on-device voice
/// when offline, when the server is slow, or when "Natural voice" is off.
@MainActor
final class Speech {
    static let shared = Speech()
    static let naturalVoiceKey = "naturalVoice"

    private let synth = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var player: AVAudioPlayer?
    private var request = 0                        // newest say() wins
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let cacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // One folder per voice, so clips from earlier voices (ElevenLabs "tts", Speechify "tts-simba35",
        // "tts-gemini38", Kokoro trial "tts-kokoro") never mix in.
        for old in ["tts", "tts-simba35", "tts-gemini38", "tts-kokoro"] {
            try? FileManager.default.removeItem(at: caches.appendingPathComponent(old, isDirectory: true))
        }
        let d = caches.appendingPathComponent("tts-gemini", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// How long to wait for the natural voice before using the on-device one.
    private let patience: Duration = .milliseconds(2500)

    var naturalVoice: Bool {
        UserDefaults.standard.object(forKey: Self.naturalVoiceKey) as? Bool ?? true
    }

    private init() {
        // Audio-session setup and voice lookup do IPC and disk I/O; keep them off the main thread.
        Task.detached(priority: .utility) {
            // Mix with the video's audio instead of stopping it.
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            let v = AVSpeechSynthesisVoice(language: "ja-JP")
            await MainActor.run { Speech.shared.voice = v }
        }
    }

    /// Call early (app launch) so the first tap is instant.
    func prewarm() {}

    func say(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        request += 1
        let mine = request
        // A single kana sound (か, きゃ…) plays its bundled clip: every TTS garbles a lone kana (か → "K", ふ → a laugh),
        // so these are recorded offline, checked by transcription, and said twice with a gap (tools/kana/make_kana.mjs).
        if Self.isSingleKana(text), playKanaClip(text) { return }
        guard naturalVoice, LessonClient.baseURL != nil, !Self.isSingleKana(text) else { return sayOnDevice(text) }

        let file = cacheFile(text)
        if let data = try? Data(contentsOf: file), play(data) { return }

        Task {
            let data = await withTaskGroup(of: Data?.self) { group in
                group.addTask { await self.fetch(text, to: file) }
                group.addTask { try? await Task.sleep(for: self.patience); return nil }
                let first = await group.next() ?? nil
                group.cancelAll()     // the fetch itself keeps going in `inFlight` and fills the cache
                return first
            }
            guard mine == request else { return }     // the user already tapped something else
            if let data, play(data) { return }
            sayOnDevice(text)
        }
    }

    /// One kana sound unit: a single kana, or a kana plus a small ゃゅょ/ぁぃぅぇぉ (きゃ), or っ/ー.
    static func isSingleKana(_ text: String) -> Bool {
        let units = Kana.units(text)
        return units.count == 1 && units[0].kana == text
    }

    /// The bundled clip for one kana sound (katakana uses its hiragana's clip), or nil (っ, ー, rare kana).
    static func kanaClipURL(_ text: String) -> URL? {
        let hira = String(String.UnicodeScalarView(text.unicodeScalars.map { u in
            (0x30A1...0x30F6).contains(u.value) ? Unicode.Scalar(u.value - 0x60)! : u
        }))
        let name = "kana_" + hira.utf16.map { String($0, radix: 16) }.joined(separator: "_")
        return Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    private func playKanaClip(_ text: String) -> Bool {
        guard let url = Self.kanaClipURL(text), let data = try? Data(contentsOf: url) else { return false }
        return play(data)
    }

    /// Fetch speech ahead of time (e.g. the next card's word) so the tap plays instantly.
    func prefetch(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard naturalVoice, !text.isEmpty, !Self.isSingleKana(text), !FileManager.default.fileExists(atPath: cacheFile(text).path) else { return }
        Task { _ = await fetch(text, to: cacheFile(text)) }
    }

    /// Stops what's playing and cancels any clip still downloading (so it can't start after the card is gone).
    func stop() {
        request += 1
        synth.stopSpeaking(at: .immediate)
        player?.stop()
    }

    // MARK: -

    private func fetch(_ text: String, to file: URL) async -> Data? {
        if let t = inFlight[text] { return await t.value }
        let t = Task<Data?, Never> {
            guard let data = try? await LessonClient.speech(text), data.count > 512 else { return nil }
            try? data.write(to: file, options: .atomic)
            return data
        }
        inFlight[text] = t
        let data = await t.value
        inFlight[text] = nil
        return data
    }

    private func play(_ data: Data) -> Bool {
        guard let p = try? AVAudioPlayer(data: data) else { return false }
        player = p
        p.volume = 1
        return p.play()
    }

    /// Beginners: the same line much slower (on-device voice), so each sound can be caught.
    func saySlowly(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        request += 1
        if Self.isSingleKana(text), playKanaClip(text) { return }   // the clip is already slow and said twice
        sayOnDevice(text, rate: 0.45)
    }

    private func sayOnDevice(_ text: String, rate: Float = 0.8) {
        let u = AVSpeechUtterance(string: text)
        u.voice = voice ?? AVSpeechSynthesisVoice(language: "ja-JP")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        synth.speak(u)
    }

    private func cacheFile(_ text: String) -> URL {
        let h = SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(h).wav")
    }

    #if DEBUG
    func debugClearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
    var debugCacheCount: Int { (try? FileManager.default.contentsOfDirectory(atPath: cacheDir.path).count) ?? 0 }
    #endif
}
