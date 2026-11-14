import Foundation

/// Small, honest insights computed from the learner's own data, plus one-line language tips for words.
/// Each is an icon + one short sentence (no walls of text).
struct Insight: Identifiable, Hashable {
    let id: String
    let symbol: String
    let text: String
}

@MainActor
enum Insights {
    static func compute(wordBook: WordBook, journey: JourneyStore, vocab: VocabStore, level: Int) -> [Insight] {
        var out: [Insight] = []
        let words = Array(wordBook.words.values)

        // Recall rate from real checks.
        let right = words.reduce(0) { $0 + $1.correct }, wrong = words.reduce(0) { $0 + $1.wrong }
        if right + wrong >= 5 {
            let pct = Int((Double(right) / Double(right + wrong) * 100).rounded())
            out.append(Insight(id: "recall", symbol: "checkmark.circle.fill",
                               text: "You get \(pct)% of checks right\(pct >= 80 ? ", time for harder words" : pct < 60 ? ". Short daily reviews help most" : "")."))
        }
        // The word that keeps slipping.
        if let w = words.filter({ $0.wrong >= 2 }).max(by: { $0.wrong < $1.wrong }), let e = vocab.byId[w.id] {
            out.append(Insight(id: "tricky", symbol: "exclamationmark.bubble.fill",
                               text: "Trickiest word: \(e.kana) (\(vocab.shortMeaning(e))), missed \(w.wrong)×. It comes back sooner."))
        }
        // When you learn.
        let hours = words.map { Calendar.current.component(.hour, from: $0.firstSeen) }
        if hours.count >= 10 {
            let buckets = Dictionary(grouping: hours) { h in h < 12 ? "morning" : h < 18 ? "afternoon" : "evening" }
            if let best = buckets.max(by: { $0.value.count < $1.value.count }) {
                out.append(Insight(id: "time", symbol: best.key == "morning" ? "sunrise.fill" : best.key == "afternoon" ? "sun.max.fill" : "moon.stars.fill",
                                   text: "You meet most new words in the \(best.key)."))
            }
        }
        // Katakana loanwords as easy wins.
        let met = words.compactMap { vocab.byId[$0.id] }
        let loans = met.filter(\.loanword).count
        if met.count >= 10, loans > 0 {
            out.append(Insight(id: "katakana", symbol: "textformat.alt",
                               text: "\(loans) of your \(met.count) words are katakana loanwords: read them and you often know the meaning."))
        }
        // Distance to the next level.
        let total = vocab.countByLevel[level] ?? 0
        let learned = wordBook.learnedCount(level: level, vocab: vocab)
        if total > 0 {
            let target = Int(Double(total) * JLPT.levelUpShare)
            out.append(Insight(id: "level", symbol: "flag.checkered",
                               text: learned >= target ? "You've learned \(learned) N\(level) words: ready to try N\(max(1, level - 1))."
                                                      : "\(target - learned) more N\(level) words learned until the next level."))
        }
        // Strongest and weakest skill in the journey.
        let counts = Skill.allCases.map { s in (s, Curriculum.allPhrases.filter { journey.skills($0.id).contains(s) }.count) }
        if let best = counts.max(by: { $0.1 < $1.1 }), let worst = counts.min(by: { $0.1 < $1.1 }), best.1 > worst.1 {
            out.append(Insight(id: "skills", symbol: worst.0.symbol,
                               text: "\(best.0.title) is your strongest skill; \(worst.0.title.lowercased()) has the most gaps."))
        }
        // Streak freeze reminder.
        if Rewards.shared.freezes > 0, wordBook.streak >= 3 {
            out.append(Insight(id: "freeze", symbol: "snowflake",
                               text: "Your \(wordBook.streak)-day streak is protected by \(Rewards.shared.freezes) streak freeze\(Rewards.shared.freezes == 1 ? "" : "s")."))
        }
        return out
    }

    /// A one-line language tip for the word just revealed (learning insight in context).
    static func tip(for e: VocabEntry) -> String? {
        if e.loanword { return "Katakana is used for words borrowed from other languages, like this one." }
        if e.isSuffix { return e.suffixNote }
        if e.pos == "verb" || e.kana.hasSuffix("る") && e.meaning.hasPrefix("to ") {
            return "Dictionary form. In polite speech it becomes 〜ます (e.g. たべる → たべます)."
        }
        if e.pos == "adj" && e.kana.hasSuffix("い") && e.kana != "きれい" {
            return "い-adjective: say it before a noun (\(e.kana) + noun) or end a sentence with it."
        }
        if e.pos == "question" { return "Question word: put か at the end of the sentence to ask (〜ですか？)." }
        if e.kana.hasSuffix("さん") { return "さん is the polite name ending, like Mr./Ms." }
        return nil
    }
}
