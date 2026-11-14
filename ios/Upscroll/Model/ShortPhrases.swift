import Foundation

/// A whole phrase taken from a real Short: the English caption line and YouTube's Japanese for it.
/// It joins the learner's own curriculum ("My phrases") and comes back as practice like any phrase.
struct ShortPhrase: Codable, Identifiable, Hashable {
    let id: String            // "<videoId>#<cue>"
    let ja: String
    let en: String
    let tiles: [String]
    let videoId: String
    let title: String
    var added = Date()
    var skills: Set<Skill> = []
    /// "jev" (judged learnable and well translated) or "rules" (offline pick).
    var pickedBy = "rules"

    /// As a curriculum phrase, so every practice screen (hear, read, build, say) works on it.
    var phrase: Phrase {
        Phrase(id: "short:\(id)", pattern: ja, meaning: en, example: ja, exampleKana: ja, exampleEnglish: en,
               tiles: tiles, matches: [], grammar: "From a Short")
    }
}

/// The learner's phrases from Shorts. Saved as JSON in Application Support.
@MainActor
final class PhraseBook: ObservableObject {
    static let shared = PhraseBook()
    @Published private(set) var phrases: [ShortPhrase] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("short-phrases.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode([ShortPhrase].self, from: d) { phrases = p }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetJourney") { phrases = []; save() }
        if ProcessInfo.processInfo.arguments.contains("-demoJourney") { seedDemo() }
        #endif
    }

    /// A synthetic place holding these phrases (practice screens draw wrong options from the same place).
    var place: Place {
        Place(id: "shorts", index: 99, name: "My Shorts", japanese: "ショート", level: "Yours",
              summary: "Phrases you met in your own feed.", scene: "scene_reel", souvenir: "souvenir_ticket",
              souvenirName: "", wordsTarget: 0, phrases: phrases.map(\.phrase), canDos: [], grammar: [], pin: (0.5, 0.5))
    }

    func contains(_ id: String) -> Bool { phrases.contains { $0.id == id } }
    func find(phraseId: String) -> ShortPhrase? { phrases.first { "short:\($0.id)" == phraseId } }

    func add(_ p: ShortPhrase) {
        guard !contains(p.id), !phrases.contains(where: { $0.ja == p.ja }) else { return }
        phrases.insert(p, at: 0)
        save()
    }

    func mark(_ phraseId: String, _ skill: Skill) {
        guard let i = phrases.firstIndex(where: { "short:\($0.id)" == phraseId }) else { return }
        phrases[i].skills.insert(skill)
        save()
    }

    /// Phrases still missing a skill, oldest first (the ones waiting longest come back first).
    func gaps(canSpeak: Bool) -> [(phrase: ShortPhrase, missing: [Skill])] {
        phrases.reversed().compactMap { p in
            let m = Skill.allCases.filter { !p.skills.contains($0) && (canSpeak || $0 != .speaking) }
            return m.isEmpty ? nil : (p, m)
        }
    }

    var fullyCovered: Int { phrases.filter { $0.skills.count == Skill.allCases.count }.count }

    func reset() { phrases = []; save() }

    func cloudMerge(_ other: [ShortPhrase]) {
        for o in other {
            if let i = phrases.firstIndex(where: { $0.id == o.id }) { phrases[i].skills.formUnion(o.skills) } else { phrases.append(o) }
        }
        phrases.sort { $0.added > $1.added }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(phrases) { try? d.write(to: url, options: .atomic) }
    }

    #if DEBUG
    private func seedDemo() {
        phrases = [
            ShortPhrase(id: "demo1#3", ja: "これはとてもかわいい", en: "this is so cute", tiles: PhraseMaker.tiles("これはとてもかわいい"),
                        videoId: "demo1", title: "Kitten sees snow", skills: [.reading, .writing], pickedBy: "jev"),
            ShortPhrase(id: "demo2#1", ja: "ちょっと待って", en: "wait a second", tiles: PhraseMaker.tiles("ちょっと待って"),
                        videoId: "demo2", title: "Street food in Osaka", skills: [.reading], pickedBy: "jev"),
        ]
        save()
    }
    #endif
}

/// Turns a caption line into a learnable phrase: picks candidate lines, splits Japanese into tiles.
enum PhraseMaker {
    /// Lines worth offering (to Jev, or to the offline rule): short, complete-looking, with real Japanese.
    static func candidates(source: [Cue], japanese: [Cue], after playedTo: Double) -> [(i: Int, en: String, ja: String)] {
        guard !japanese.isEmpty else { return [] }
        var out: [(Int, String, String)] = []
        for (i, cue) in source.enumerated() where cue.start >= playedTo + 1 {
            let en = cue.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            let words = en.split(separator: " ").count
            guard (2...8).contains(words), !en.contains("["), !en.contains("♪"), !en.contains("http") else { continue }
            guard let ja = bestOverlap(cue, japanese)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  Romanize.isJapanese(ja), (3...18).contains(ja.count) else { continue }
            out.append((i, en, ja))
            if out.count >= 12 { break }
        }
        return out
    }

    /// Offline pick: the shortest line that sounds like something people say (exclamations, questions first).
    static func rulePick(_ c: [(i: Int, en: String, ja: String)]) -> (i: Int, en: String, ja: String)? {
        c.min { a, b in score(a.en) < score(b.en) }
    }

    private static func score(_ en: String) -> Double {
        let words = Double(en.split(separator: " ").count)
        let bonus = (en.hasSuffix("!") || en.hasSuffix("?")) ? -1.5 : 0
        return abs(words - 4) + bonus
    }

    static func bestOverlap(_ cue: Cue, _ ja: [Cue]) -> Cue? {
        func ov(_ a: Cue) -> Double { max(0, min(a.end, cue.end) - max(a.start, cue.start)) }
        guard let b = ja.max(by: { ov($0) < ov($1) }), ov(b) > 0.3 * (cue.end - cue.start) else { return nil }
        return b
    }

    /// Japanese → 2…6 tiles: words from the system tokenizer, with verb endings and small particles
    /// glued so tiles are meaningful chunks (ちょっと / 待って, not 待っ / て).
    static func tiles(_ ja: String) -> [String] {
        let text = ja.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        let cf = text as CFString
        guard let tok = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
                                                kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale) else { return [text] }
        // Words from the tokenizer; text it skips between words (！、？) is kept and glued to the word before.
        var words: [String] = []
        var lastEnd = 0
        func piece(_ loc: Int, _ len: Int) -> String { CFStringCreateWithSubstring(nil, cf, CFRange(location: loc, length: len)) as String? ?? "" }
        while CFStringTokenizerAdvanceToNextToken(tok) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tok)
            if r.location > lastEnd {
                let gap = piece(lastEnd, r.location - lastEnd)
                if words.isEmpty { words.append(gap) } else { words[words.count - 1] += gap }
            }
            words.append(piece(r.location, r.length))
            lastEnd = r.location + r.length
        }
        let total = CFStringGetLength(cf)
        if lastEnd < total {
            let gap = piece(lastEnd, total - lastEnd)
            if words.isEmpty { words.append(gap) } else { words[words.count - 1] += gap }
        }
        let glue: Set<String> = ["て", "で", "た", "だ", "ます", "ました", "ません", "です", "でした", "ない", "なかった", "たい", "てる", "ている",
                                 "う", "よう", "ん", "の", "ね", "よ", "な", "か", "わ", "さ", "ちゃう", "れる", "られる", "せる", "っ", "ば", "し"]
        var chunks: [String] = []
        for w in words {
            let isPunct = w.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) || "！？、。!?".unicodeScalars.contains($0) }
            if let last = chunks.indices.last, glue.contains(w) || isPunct || w.hasPrefix("っ") {
                chunks[last] += w
            } else {
                chunks.append(w)
            }
        }
        // At most 6 tiles: merge the shortest neighbouring pair until it fits.
        while chunks.count > 6 {
            var best = 0
            for i in 0..<(chunks.count - 1) where chunks[i].count + chunks[i + 1].count < chunks[best].count + chunks[best + 1].count { best = i }
            chunks[best] += chunks.remove(at: best + 1)
        }
        // One tile isn't a puzzle: split it in two.
        if chunks.count == 1, let only = chunks.first, only.count >= 4 {
            let mid = only.index(only.startIndex, offsetBy: only.count / 2)
            chunks = [String(only[..<mid]), String(only[mid...])]
        }
        return chunks
    }
}
