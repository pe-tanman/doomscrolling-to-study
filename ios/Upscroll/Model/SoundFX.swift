import AVFoundation
import UIKit

/// Short UI sounds (made with ElevenLabs sound effects, see tools/make_sfx.mjs), played over the Short
/// without stopping it. Each sound is a bundled `sfx_<name>.mp3`; a missing file is simply silent.
/// Off with Settings → Customize → Sound effects.
@MainActor
enum SoundFX {
    enum Sound: String, CaseIterable {
        case correct      // right answer: bright two-note chime
        case wrong        // wrong answer: soft low "nope"
        case milestone    // progress message: gentle rising chime
        case unlock       // new practice type / kana complete: short fanfare
        case reward       // streak freeze / skip ticket / gift: sparkle
        case pop          // a card opens over the Short: soft bubble pop
    }

    static let enabledKey = "soundEffects"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Quieter than speech, so a sound never covers the Japanese voice.
    private static let volume: [Sound: Float] = [.correct: 0.55, .wrong: 0.45, .milestone: 0.5, .unlock: 0.6, .reward: 0.5, .pop: 0.35]
    private static var players: [Sound: AVAudioPlayer] = [:]

    /// Load every sound up front so the first one plays instantly.
    static func prewarm() {
        for s in Sound.allCases where players[s] == nil {
            guard let url = Bundle.main.url(forResource: "sfx_\(s.rawValue)", withExtension: "mp3"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.prepareToPlay()
            players[s] = p
        }
    }

    static func play(_ s: Sound) {
        guard enabled else { return }
        if players[s] == nil { prewarm() }
        guard let p = players[s] else { return }
        p.volume = volume[s] ?? 0.5
        p.currentTime = 0
        p.play()
    }

    // MARK: Sound + haptic together (one call at every answer in the app)

    static func answered(correct: Bool) {
        play(correct ? .correct : .wrong)
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
    }
}
