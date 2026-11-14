import Foundation

struct LearnerSettings: Codable, Equatable {
    var scriptLevel: ScriptLevel = .kanaRomaji
    /// Learning words per video (the user asked for at least two).
    var wordsPerVideo = 2
    /// Pause the video after the line with a learning word, until the learner taps it.
    var pauseOnWord = true
    /// Speak the word automatically when the card appears. On by default: beginners can't read kana yet.
    var autoSpeak = true
    /// Show the full machine-translated Japanese line on the word card.
    var showJapaneseSentence = true
    /// Daily goal: words met per day.
    var dailyGoal = 10
    /// Debug: show the Japanese caption line under the subtitles while playing.
    var showJapaneseLineWhilePlaying = false
    /// Let TypeSafe Jev choose the learning words (falls back to on-device rules when offline).
    var smartPicks = true
    /// JLPT level being learned: 5 = N5 … 1 = N1. Words at this level and easier are taught.
    var jlptLevel = 5
    /// Daily scroll limit in minutes (0 = off). At the limit the session recap offers a "good stop".
    var dailyLimitMinutes = 20
    /// Ask YouTube for Japanese Shorts (hl=ja&gl=JP on the feed URL).
    var japaneseFeed = false
    /// About 1 in 6 swipes is an Upscroll original card or mini-reel built for your gaps.
    var originals = true
    /// Cards: at least one question on every Short (1), or 0 = only when I ask (open あ → Review).
    /// (Every 2nd / 3rd were removed: a Short with no question teaches little. Old values load as 1.)
    var cardEvery = 1
    /// Quiet mode: no "say it out loud" tasks in the feed (for places you can't speak).
    var speakingInFeed = true
    /// Why they're learning (onboarding): steers the personal path Jev builds. See `LearningGoal`.
    var goal = LearningGoal.culture.rawValue

    init() {}

    // Tolerant decoding: settings saved by older versions keep their values when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LearnerSettings()
        scriptLevel = try c.decodeIfPresent(ScriptLevel.self, forKey: .scriptLevel) ?? d.scriptLevel
        wordsPerVideo = try c.decodeIfPresent(Int.self, forKey: .wordsPerVideo) ?? d.wordsPerVideo
        pauseOnWord = try c.decodeIfPresent(Bool.self, forKey: .pauseOnWord) ?? d.pauseOnWord
        autoSpeak = try c.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? d.autoSpeak
        showJapaneseSentence = try c.decodeIfPresent(Bool.self, forKey: .showJapaneseSentence) ?? d.showJapaneseSentence
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? d.dailyGoal
        showJapaneseLineWhilePlaying = try c.decodeIfPresent(Bool.self, forKey: .showJapaneseLineWhilePlaying) ?? d.showJapaneseLineWhilePlaying
        smartPicks = try c.decodeIfPresent(Bool.self, forKey: .smartPicks) ?? d.smartPicks
        jlptLevel = try c.decodeIfPresent(Int.self, forKey: .jlptLevel) ?? d.jlptLevel
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes) ?? d.dailyLimitMinutes
        japaneseFeed = try c.decodeIfPresent(Bool.self, forKey: .japaneseFeed) ?? d.japaneseFeed
        originals = try c.decodeIfPresent(Bool.self, forKey: .originals) ?? d.originals
        cardEvery = try c.decodeIfPresent(Int.self, forKey: .cardEvery) ?? d.cardEvery
        speakingInFeed = try c.decodeIfPresent(Bool.self, forKey: .speakingInFeed) ?? d.speakingInFeed
        goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? d.goal
    }

    private static let key = "learnerSettings.v1"

    static func load() -> LearnerSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              var s = try? JSONDecoder().decode(LearnerSettings.self, from: data) else { return LearnerSettings() }
        // Settings removed from the screen: "Pause on each new word" off is now the card pace "Only when I ask",
        // and smarter word choice is always on (the plan's daily allowance decides when it falls back).
        if !s.pauseOnWord { s.pauseOnWord = true; s.cardEvery = 0 }
        if s.cardEvery > 1 { s.cardEvery = 1 }
        s.smartPicks = true
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}
