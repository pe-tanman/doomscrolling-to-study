import Foundation

// MARK: - Kana practice

/// Which basic hiragana sounds the learner has picked right (feed sound drills and Review "Kana sounds").
/// Kana practice is complete when every one has been answered right once.
@MainActor
final class KanaProgress: ObservableObject {
    static let shared = KanaProgress()
    /// The sounds the drill asks: basic hiragana except を (sounds like お) and ん (too short to hear alone).
    static let drillSet: [String] = Kana.basicHiragana.filter { $0 != "ん" && $0 != "を" }

    @Published private(set) var known: Set<String>
    private let key = "kana.known.v1"

    private init() {
        known = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetJourney") { known = []; save(); Unlocks.debugReset(); Nudges.debugReset() }
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-kanaKnown"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let n = Int(ProcessInfo.processInfo.arguments[i + 1]) {
            known = Set(Self.drillSet.prefix(n)); save()   // UI tests: start close to completion
        }
        #endif
    }

    var total: Int { Self.drillSet.count }
    var count: Int { known.intersection(Self.drillSet).count }
    var isComplete: Bool { count >= total }
    var remaining: [String] { Self.drillSet.filter { !known.contains($0) } }

    /// A kana answered right (katakana counts for the same sound).
    func recordRight(_ kana: String) {
        let h = kana.applyingTransform(.hiraganaToKatakana, reverse: true) ?? kana
        guard Self.drillSet.contains(h), !known.contains(h) else { return }
        known.insert(h)
        save()
    }

    /// Recently asked sounds, so the same few don't come back to back.
    private var recent: [String] = []

    /// Next sound to drill: a random one not known yet (never chart order like あいうえお, which turns into
    /// guessing the sequence instead of listening), avoiding the last few asked; once all are known, any.
    func nextDrill() -> String {
        let pool = remaining.isEmpty ? Self.drillSet : remaining
        let fresh = pool.filter { !recent.contains($0) }
        let k = (fresh.isEmpty ? pool : fresh).randomElement() ?? "か"
        recent.append(k)
        if recent.count > min(4, max(0, pool.count - 1)) { recent.removeFirst(recent.count - min(4, max(0, pool.count - 1))) }
        return k
    }

    func reset() { known = []; save() }
    private func save() { UserDefaults.standard.set(Array(known), forKey: key) }
}

// MARK: - What unlocks next, and how long it takes

/// One goal on the way to the next practice type (or to finishing kana practice).
struct UnlockGoal: Identifiable {
    let id: String
    let title: String       // "Kana sounds", "Patterns"
    let detail: String      // "18 of 44 sounds"
    let progress: Double    // 0…1
    let estimate: String    // "about 26 more sound cards (~9 min)"
    let symbol: String
}

/// Something the learner just unlocked: shown over the feed with a short burst effect.
struct UnlockEvent: Identifiable, Equatable {
    let id = UUID()
    let title: String       // "Unlocked: Chunks"
    let message: String
    let symbol: String
}

enum Unlocks {
    /// Seconds a learner spends per feed card, roughly (watching to the card + answering).
    private static let secondsPerCard = 20.0

    private static func minutes(_ cards: Int) -> String {
        let m = max(1, Int((Double(cards) * secondsPerCard / 60).rounded(.up)))
        return m == 1 ? "~1 min" : "~\(m) min"
    }

    /// Words become "learned" only after spaced reviews over days, so word goals are estimated in days
    /// from the learner's daily goal (and never less than the 3 days a first review takes to stick).
    private static func days(words: Int, dailyGoal: Int) -> String {
        guard words > 0 else { return "" }
        let d = max(3, Int((Double(words) / Double(max(1, dailyGoal / 2))).rounded(.up)))
        return "about \(d) days"
    }

    @MainActor
    static func kanaGoal(_ k: KanaProgress = .shared) -> UnlockGoal? {
        guard !k.isComplete else { return nil }
        let left = k.total - k.count
        return UnlockGoal(id: "kana", title: "Kana sounds", detail: "\(k.count) of \(k.total) sounds",
                          progress: Double(k.count) / Double(k.total),
                          estimate: "\(left) more sound card\(left == 1 ? "" : "s") (\(minutes(left)))",
                          symbol: "character.ja")
    }

    /// The next practice type on the ladder and what's still needed for it.
    @MainActor
    static func ladderGoal(wordsLearned w: Int, grammar g: GrammarBook = .shared, dailyGoal: Int) -> UnlockGoal? {
        let stage = LadderStage.current(wordsLearned: w, grammar: g)
        func goal(_ next: LadderStage, words needWords: Int, tier: Int, grammarNeed: Int, grammarNoun: String) -> UnlockGoal {
            let wLeft = max(0, needWords - w)
            let gLeft = tier == 0 ? 0 : max(0, grammarNeed - g.solidCount(tier: tier))
            let wDone = Double(min(w, needWords)) / Double(needWords)
            let gDone = tier == 0 ? 1 : Double(grammarNeed - gLeft) / Double(grammarNeed)
            var parts: [String] = []
            if wLeft > 0 { parts.append("\(wLeft) more word\(wLeft == 1 ? "" : "s") learned") }
            // A grammar point needs 2 right answers on different days; grammar cards come about every 3rd Short.
            if gLeft > 0 { parts.append("\(gLeft) more \(grammarNoun) right twice") }
            var when: [String] = []
            if wLeft > 0 { when.append(days(words: wLeft, dailyGoal: dailyGoal)) }
            if gLeft > 0 { when.append("~\(gLeft * 2 * 3) Shorts over 2+ days") }
            return UnlockGoal(id: "ladder-\(next.rawValue)", title: next.title,
                              detail: parts.joined(separator: " · "),
                              progress: tier == 0 ? wDone : (wDone + gDone) / 2,
                              estimate: when.joined(separator: " · "),
                              symbol: next == .chunks ? "square.stack.3d.up.fill" : next == .patterns ? "arrow.triangle.branch" : "text.bubble.fill")
        }
        switch stage {
        case .words: return goal(.chunks, words: 10, tier: 0, grammarNeed: 0, grammarNoun: "")
        case .chunks: return goal(.patterns, words: 40, tier: 1, grammarNeed: 3, grammarNoun: "particles")
        case .patterns: return goal(.sentences, words: 120, tier: 2, grammarNeed: 3, grammarNoun: "endings")
        case .sentences: return nil
        }
    }

    // MARK: Detecting an unlock

    private static let stageKey = "unlocks.lastStage"
    private static let kanaDoneKey = "unlocks.kanaDone"

    /// Call after any answer. Returns an event the first time a new practice type or kana completion is reached.
    @MainActor
    static func check(wordsLearned: Int) -> UnlockEvent? {
        let d = UserDefaults.standard
        if KanaProgress.shared.isComplete, !d.bool(forKey: kanaDoneKey) {
            d.set(true, forKey: kanaDoneKey)
            return UnlockEvent(title: "Kana sounds complete!",
                               message: "You can hear all \(KanaProgress.shared.total) basic sounds. Words take over from here.",
                               symbol: "character.ja")
        }
        let stage = LadderStage.current(wordsLearned: wordsLearned, grammar: .shared)
        let last = d.object(forKey: stageKey) as? Int
        d.set(stage.rawValue, forKey: stageKey)
        // First run (nothing saved yet): just remember where the learner is, no celebration.
        guard let last, stage.rawValue > last else { return nil }
        return UnlockEvent(title: "Unlocked: \(stage.title)", message: stage.blurb,
                           symbol: stage == .chunks ? "square.stack.3d.up.fill" : stage == .patterns ? "arrow.triangle.branch" : "text.bubble.fill")
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: stageKey)
        UserDefaults.standard.removeObject(forKey: kanaDoneKey)
    }
    #endif
}

// MARK: - Progress nudges while scrolling

/// A short, non-blocking "you're getting somewhere" message over the feed.
struct ProgressNudge: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
    /// Shown as a small bar when the message is about getting closer to something.
    var progress: Double? = nil
}

enum Nudges {
    private static let wordSteps = [5, 10, 20, 30, 50, 75, 100]
    private static let unlockSteps = [25, 50, 75, 90]
    private static let kanaSteps = [10, 20, 30, 40]

    private static func dayKey() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "nudges.\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The next milestone not shown yet, or nil. Marks it shown.
    @MainActor
    static func next(newWordsToday: Int, dailyGoal: Int, wordsLearned: Int) -> ProgressNudge? {
        let d = UserDefaults.standard
        var today = Set(d.stringArray(forKey: dayKey()) ?? [])
        var ever = Set(d.stringArray(forKey: "nudges.ever") ?? [])
        func once(_ key: String, daily: Bool) -> Bool {
            if daily { guard today.insert(key).inserted else { return false }; d.set(Array(today), forKey: dayKey()) }
            else { guard ever.insert(key).inserted else { return false }; d.set(Array(ever), forKey: "nudges.ever") }
            return true
        }

        // 1) Closer to the next practice type (the most exciting one).
        let stage = LadderStage.current(wordsLearned: wordsLearned, grammar: .shared)
        if let next = LadderStage.allCases.first(where: { $0 > stage }),
           let goal = Unlocks.ladderGoal(wordsLearned: wordsLearned, dailyGoal: dailyGoal) {
            let pct = Int(goal.progress * 100)
            if let step = unlockSteps.last(where: { pct >= $0 }), once("unlock-\(next.rawValue)-\(step)", daily: false) {
                return ProgressNudge(text: "\(step)% to unlock \(next.title)!", symbol: "lock.open.fill", progress: goal.progress)
            }
        }
        // 2) Daily goal reached.
        if newWordsToday >= dailyGoal, once("goal", daily: true) {
            return ProgressNudge(text: "Daily goal done: \(newWordsToday) new words today!", symbol: "target")
        }
        // 3) Words today.
        if let step = wordSteps.last(where: { newWordsToday >= $0 }), once("words-\(step)", daily: true) {
            return ProgressNudge(text: "You learned \(step) new words today!", symbol: "sparkles",
                                 progress: Double(min(newWordsToday, dailyGoal)) / Double(max(1, dailyGoal)))
        }
        // 4) Kana sounds.
        let k = KanaProgress.shared
        if !k.isComplete, let step = kanaSteps.last(where: { k.count >= $0 }), once("kana-\(step)", daily: false) {
            return ProgressNudge(text: "\(k.count) of \(k.total) kana sounds!", symbol: "character.ja",
                                 progress: Double(k.count) / Double(k.total))
        }
        return nil
    }

    #if DEBUG
    static func debugReset() {
        UserDefaults.standard.removeObject(forKey: dayKey())
        UserDefaults.standard.removeObject(forKey: "nudges.ever")
    }
    #endif
}
