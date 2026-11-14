import Foundation

// MARK: - The question ladder
//
// Word → sentence was too big a jump. Questions now climb five rungs, and the learner's own progress
// decides which rungs the feed uses:
//   1 Sounds     kana drills (brand-new learners)
//   2 Words      the yellow word swapped into the subtitles
//   3 Chunks     a word + its particle / ending, as a blank in the Short's own Japanese line (ラーメン【が】)
//   4 Patterns   verb / adjective endings that change the meaning (食べ【たい】, 食べ【てる】, 【から】)
//   5 Sentences  the whole line from the Short: read it, build it, say it
// Chunk and pattern questions come from the Short being watched: the app finds the grammar in YouTube's
// Japanese for a caption line, Jev checks it (right grammar? good translation? only one right answer?),
// and the Short pauses right after that line.

enum LadderStage: Int, Codable, CaseIterable, Comparable {
    case words = 2, chunks = 3, patterns = 4, sentences = 5

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .words: return "Words"
        case .chunks: return "Chunks"
        case .patterns: return "Patterns"
        case .sentences: return "Sentences"
        }
    }

    var blurb: String {
        switch self {
        case .words: return "Single words swapped into your Shorts."
        case .chunks: return "Words with their particles: ラーメンが, えきに."
        case .patterns: return "Endings that change the meaning: たべたい, たべてる."
        case .sentences: return "Whole lines from your Shorts: read, build and say them."
        }
    }

    /// Hardest grammar tier asked at this stage.
    var maxTier: Int {
        switch self {
        case .words: return 0
        case .chunks: return 1
        case .patterns: return 2
        case .sentences: return 3
        }
    }

    /// Where the learner is now. Words learned and grammar answered right both have to grow to move up,
    /// so nobody lands in whole-sentence building on vocabulary alone.
    @MainActor static func current(wordsLearned: Int, grammar: GrammarBook) -> LadderStage {
        if wordsLearned < 10 { return .words }
        if wordsLearned < 40 || grammar.solidCount(tier: 1) < 3 { return .chunks }
        if wordsLearned < 120 || grammar.solidCount(tier: 2) < 3 { return .patterns }
        return .sentences
    }

    /// What's missing to reach the next stage (shown in Progress).
    @MainActor static func nextStep(wordsLearned: Int, grammar: GrammarBook) -> String? {
        switch current(wordsLearned: wordsLearned, grammar: grammar) {
        case .words: return "Learn \(10 - wordsLearned) more words to unlock chunks."
        case .chunks:
            let g = max(0, 3 - grammar.solidCount(tier: 1)), w = max(0, 40 - wordsLearned)
            return [w > 0 ? "\(w) more words" : nil, g > 0 ? "\(g) more particles right twice" : nil].compactMap { $0 }.joined(separator: " and ") + " to unlock patterns."
        case .patterns:
            let g = max(0, 3 - grammar.solidCount(tier: 2)), w = max(0, 120 - wordsLearned)
            return [w > 0 ? "\(w) more words" : nil, g > 0 ? "\(g) more endings right twice" : nil].compactMap { $0 }.joined(separator: " and ") + " to unlock sentences."
        case .sentences: return nil
        }
    }
}

// MARK: - Grammar points

/// One grammar point the feed can ask about as a fill-in-the-blank on a real caption line.
struct GrammarPoint: Identifiable, Hashable {
    let id: String
    /// 1 chunks (particles, です/ます), 2 patterns (endings), 3 sentence-level.
    let tier: Int
    /// Curriculum place it belongs to.
    let place: String
    /// Shown as the card title: "を", "〜たい".
    let title: String
    /// For Jev and the card: what it does.
    let meaning: String
    /// One-line beginner explanation on the reveal.
    let tip: String
    /// Regex on the Japanese line; capture group 1 is the piece to blank out.
    let pattern: String
    /// Wrong options for a given piece (Jev drops any that would also be right).
    let distractors: (String) -> [String]

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A grammar point found in one line: where the piece is and what to offer instead.
struct GrammarHit: Hashable {
    let point: GrammarPoint
    let piece: String
    let before: String
    let after: String
    let distractors: [String]
}

enum GrammarCatalog {
    private static let kanaOrKanji = "[\\p{Han}ぁ-んァ-ンー]"

    /// In ladder order: earlier points are introduced first.
    static let points: [GrammarPoint] = [
        GrammarPoint(id: "ka_q", tier: 1, place: "cafe", title: "〜か？", meaning: "turns a polite sentence into a question",
                     tip: "か at the end = a question mark you can hear.",
                     pattern: "(?:です|ます|でしょう)(か)(?:[？?！!。]|$)",
                     distractors: { _ in ["ね", "よ"] }),
        GrammarPoint(id: "wo", tier: 1, place: "cafe", title: "を", meaning: "marks the thing you act on (eat it, buy it, watch it)",
                     tip: "を points at what the action is done to: コーヒーを のむ = drink coffee.",
                     pattern: "\(kanaOrKanji)(を)\(kanaOrKanji)",
                     distractors: { _ in ["に", "で", "が"] }),
        GrammarPoint(id: "wa", tier: 1, place: "cafe", title: "は", meaning: "marks the topic: as for X …",
                     tip: "は (said \"wa\") sets the topic: わたしは… = as for me…",
                     pattern: "(?<!こんにち|こんばん|で|に|と)(?<=[\\p{Han}ァ-ンーれこそあ])(は)(?=[\\p{Han}ぁ-んァ-ン、])",
                     distractors: { _ in ["を", "に"] }),
        GrammarPoint(id: "ga_like", tier: 1, place: "cafe", title: "が + すき / ほしい", meaning: "marks what you like, want or can do",
                     tip: "With すき, ほしい, わかる and できる, the thing goes with が: ねこが すき.",
                     pattern: "\(kanaOrKanji)(が)(?=.{0,4}(?:好き|すき|大好き|だいすき|欲し|ほし|分か|わか|でき|上手|じょうず))",
                     distractors: { _ in ["を", "に", "で"] }),
        GrammarPoint(id: "no", tier: 1, place: "cafe", title: "の", meaning: "links two nouns: X's Y, the Y of X",
                     tip: "の joins nouns like 's: わたしの ねこ = my cat.",
                     pattern: "(?<=[\\p{Han}ァ-ンー]|わたし|ぼく|あなた|きみ)(の)(?=[\\p{Han}ァ-ンー])",
                     distractors: { _ in ["を", "に", "が"] }),
        GrammarPoint(id: "masu", tier: 1, place: "station", title: "ます · ません · ました", meaning: "polite verb ending: does / doesn't / did",
                     tip: "ます = do, ません = don't, ました = did. Same stem, the ending carries the meaning.",
                     pattern: "(?<=[\\p{Han}ぁ-ん])(ましょう|ました|ません|ます)(?!ん)",
                     distractors: { p in ["ます", "ません", "ました"].filter { $0 != p } }),
        GrammarPoint(id: "desu", tier: 1, place: "cafe", title: "です · でした", meaning: "polite \"is\" / \"was\"",
                     tip: "です = is, でした = was. It goes at the very end.",
                     pattern: "(?<=[\\p{Han}ぁ-んァ-ンー])(でした|です)(?!か)",
                     distractors: { p in p == "です" ? ["でした", "ですか"] : ["です", "ですか"] }),
        GrammarPoint(id: "ni_dest", tier: 1, place: "station", title: "に (where to)", meaning: "marks where you go or arrive",
                     tip: "に after a place + いく / くる / かえる = to that place.",
                     pattern: "\(kanaOrKanji)(に)(?=.{0,3}(?:行|い[きくっかこ]|来|き[まてた]|帰|かえ|着|つ[きくい]|戻|もど))",
                     distractors: { _ in ["を", "が"] }),
        GrammarPoint(id: "de_place", tier: 1, place: "station", title: "で (where it happens)", meaning: "marks where an action happens, or what you use",
                     tip: "で = at / with: えきで かう = buy at the station.",
                     pattern: "\(kanaOrKanji)(で)(?=.{0,6}(?:食べ|たべ|飲|の[みむん]|買|か[いうっ]|会|あ[いうっ]|遊|あそ|働|はたら|見|勉強|べんきょう))",
                     distractors: { _ in ["を", "が"] }),

        GrammarPoint(id: "tai", tier: 2, place: "shrine", title: "〜たい", meaning: "want to do (after the verb stem)",
                     tip: "Verb stem + たい = want to: たべたい = want to eat.",
                     pattern: "(?<=[\\p{Han}ぁ-ん])(たくない|たい)(?![ぁ-ん&&[^よねなのし]])",
                     distractors: { p in p == "たい" ? ["ます", "ました", "ません"] : ["たい", "ません"] }),
        GrammarPoint(id: "teiru", tier: 2, place: "shrine", title: "〜てる / 〜ている", meaning: "is doing right now (ongoing)",
                     tip: "て-form + いる (often just てる) = doing it now: たべてる = eating.",
                     pattern: "(?<=[\\p{Han}ぁ-んっ])(ています|ている|てる|でいます|でいる|でる)(?![ぁ-ん&&[^よねなの]])",
                     distractors: { p in p.hasPrefix("で") ? ["だ", "でください"] : ["た", "てください"] }),
        GrammarPoint(id: "tekudasai", tier: 2, place: "shrine", title: "〜てください", meaning: "please do (a polite request)",
                     tip: "て-form + ください = please do it: まってください = please wait.",
                     pattern: "(?<=[\\p{Han}ぁ-んっ])(てください|でください|て下さい|で下さい)",
                     distractors: { p in p.hasPrefix("で") ? ["だ", "でいる"] : ["た", "ている"] }),
        GrammarPoint(id: "kara", tier: 2, place: "shrine", title: "〜から (because)", meaning: "gives a reason: because …, so …",
                     tip: "Reason + から = because: さむいから = because it's cold.",
                     pattern: "(?<=[いだすたるうくぐむぶつ]|です|ます)(から)",
                     distractors: { _ in ["けど", "まで"] }),
        GrammarPoint(id: "kedo", tier: 2, place: "shrine", title: "〜けど", meaning: "but, although",
                     tip: "けど = but: おいしいけど たかい = tasty but expensive.",
                     pattern: "(?<=[\\p{Han}ぁ-ん])(けど|けれど)",
                     distractors: { _ in ["から", "まで"] }),

        GrammarPoint(id: "katta", tier: 3, place: "ramen", title: "〜かった", meaning: "past of an い-adjective (was …)",
                     tip: "い-adjective: drop い, add かった = was: おいしかった = was tasty.",
                     pattern: "(?<=[\\p{Han}][ぁ-ん]{0,3}|[ぁ-ん]{2,4})(かった|くない)",
                     distractors: { p in p == "かった" ? ["い", "くない"] : ["い", "かった"] }),
        GrammarPoint(id: "omou", tier: 3, place: "ramen", title: "〜と思う", meaning: "I think …",
                     tip: "Opinion + と思う = I think: いいと思う = I think it's good.",
                     pattern: "(と思う|と思います|と思った|とおもう|とおもいます)",
                     distractors: { p in p.contains("ます") ? ["と言います", "かもしれません"] : ["と言う", "かもしれない"] }),
        GrammarPoint(id: "mitai", tier: 3, place: "castle", title: "〜みたい", meaning: "looks like, seems like",
                     tip: "みたい = looks like: ねこみたい = looks like a cat.",
                     pattern: "(?<=[\\p{Han}ぁ-んァ-ンー])(みたい)",
                     distractors: { _ in ["だけ", "から"] }),
        GrammarPoint(id: "kamo", tier: 3, place: "castle", title: "〜かも", meaning: "maybe, might",
                     tip: "かも (かもしれない) = maybe: あめかも = might rain.",
                     pattern: "(?<=[\\p{Han}ぁ-んァ-ンー])(かもしれません|かもしれない|かも)(?!の)",
                     distractors: { _ in ["から", "だけ"] }),
    ]

    static let byId: [String: GrammarPoint] = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })
    static func order(_ id: String) -> Int { points.firstIndex { $0.id == id } ?? .max }

    /// Every grammar point in a Japanese line (first occurrence per point).
    static func detect(in ja: String, maxTier: Int = 3) -> [GrammarHit] {
        let text = ja.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        let ns = text as NSString
        var hits: [(hit: GrammarHit, range: NSRange)] = []
        for p in points where p.tier <= maxTier {
            guard let re = try? NSRegularExpression(pattern: p.pattern),
                  let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { continue }
            let r = m.range(at: 1)
            let piece = ns.substring(with: r)
            let before = ns.substring(to: r.location)
            let after = ns.substring(from: r.location + r.length)
            let d = p.distractors(piece).filter { $0 != piece }
            guard d.count >= 2 else { continue }
            hits.append((GrammarHit(point: p, piece: piece, before: before, after: after, distractors: d), r))
        }
        // A piece inside a longer one is the longer one's (猫みたい is みたい, not 〜たい).
        return hits.filter { h in
            !hits.contains { o in o.range.length > h.range.length && NSIntersectionRange(o.range, h.range).length == h.range.length }
        }.map(\.hit)
    }

    /// Points in a line the learner hasn't met yet (sentence cards allow at most one: i + 1, not a leap).
    @MainActor static func unmet(in ja: String, book: GrammarBook) -> [GrammarPoint] {
        detect(in: ja).map(\.point).filter { book.progress($0.id) == nil }
    }

    /// Tiles for "build the chunk": the word before the piece, the piece, the word after. When the piece ends
    /// the line, the word before that comes in too (with its particle), so ラーメンが / 食べ / たい, not just 食べ / たい.
    static func chunk(before: String, piece: String, after: String) -> [String] {
        let left = words(before)
        guard let last = left.last else { return [piece] }
        var tiles = [last, piece]
        if let right = words(after).first { tiles.append(right) }
        else if left.count >= 2 {
            var prev = left[left.count - 2]
            if prev.count == 1, left.count >= 3 { prev = left[left.count - 3] + prev }   // noun + particle as one tile
            tiles.insert(prev, at: 0)
        }
        return tiles
    }

    /// Word boundaries (for chunk tiles).
    static func words(_ s: String) -> [String] {
        let cf = s as CFString
        guard let tok = CFStringTokenizerCreate(nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
                                                kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale) else { return [s] }
        var out: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tok) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tok)
            if let w = CFStringCreateWithSubstring(nil, cf, r) as String? { out.append(w) }
        }
        return out
    }
}

// MARK: - Words around the blank

/// One word in a grammar question's line, with what the learner knows about it.
struct WordGloss: Hashable {
    enum Status: String { case known, met, new }
    let text: String
    let meaning: String
    let status: Status
    let entryId: String
}

/// Grammar questions should be about the grammar, not the vocabulary: the other words in the line are ones
/// the learner knows, and any new one is translated right on the card.
enum GrammarGloss {
    /// Endings stripped before looking a word up (食べました → 食べ → 食べる).
    private static let endings = ["ませんでした", "ました", "ません", "ましょう", "ます", "たくない", "たい", "ています", "ている", "てる",
                                  "でいる", "でる", "てください", "でください", "かった", "くない", "なかった", "ない", "です", "でした",
                                  "た", "だ", "て", "で"]
    private static let iToU: [Character: Character] = ["き": "く", "ぎ": "ぐ", "し": "す", "ち": "つ", "に": "ぬ", "び": "ぶ", "み": "む", "り": "る", "い": "う"]
    /// Tiny words every learner of this level has seen; never glossed (particles, sentence endings).
    private static let function: Set<String> = ["は", "が", "を", "に", "で", "と", "も", "の", "か", "ね", "よ", "へ", "や", "な", "わ", "って",
                                                "から", "まで", "けど", "です", "ます", "だ", "た", "て", "し", "さ", "ん", "の?", "よね"]

    /// Dictionary entry for a word as it appears in a line (conjugated verbs and adjectives included).
    static func entry(for raw: String, vocab: VocabStore) -> VocabEntry? {
        let w = raw.trimmingCharacters(in: CharacterSet(charactersIn: "！？!?、。…「」 　"))
        guard !w.isEmpty else { return nil }
        var stems = [w]
        for e in endings where w.hasSuffix(e) && w.count > e.count { stems.append(String(w.dropLast(e.count))) }
        for s in stems {
            if let e = vocab.byJapanese[s] { return e }
            // Verb / adjective stems: 食べ → 食べる, 行き → 行く, 待っ → 待つ, 飲ん → 飲む, おいし → おいしい.
            var forms = [s + "る", s + "い", s + "う"]
            if let last = s.last, let u = iToU[last] { forms.append(String(s.dropLast()) + String(u)) }
            if s.hasSuffix("っ") { let b = s.dropLast(); forms += [b + "つ", b + "う", b + "る"] }
            if s.hasSuffix("ん") { let b = s.dropLast(); forms += [b + "む", b + "ぶ", b + "ぬ"] }
            if let e = forms.lazy.compactMap({ vocab.byJapanese[$0] }).first { return e }
        }
        return nil
    }

    /// Content words of a piece of a line, each with its meaning and the learner's status.
    /// nil when a content word can't be translated (a name, slang): such a line would test vocabulary, not grammar.
    /// Katakana words are let through (their sound is the meaning).
    @MainActor static func gloss(_ text: String, vocab: VocabStore, book: WordBook) -> [WordGloss]? {
        var out: [WordGloss] = []
        for w in GrammarCatalog.words(text) {
            let t = w.trimmingCharacters(in: CharacterSet(charactersIn: "！？!?、。…「」 　"))
            if t.isEmpty || function.contains(t) { continue }
            guard let e = entry(for: t, vocab: vocab) else {
                if t.unicodeScalars.allSatisfy({ (0x30A0...0x30FF).contains($0.value) }) { continue }   // カタカナ
                if t.count <= 2, t.unicodeScalars.allSatisfy({ (0x3040...0x309F).contains($0.value) }) { continue }   // small kana bits
                return nil
            }
            if out.contains(where: { $0.entryId == e.id }) { continue }
            let p = book.progress(e.id)
            let status: WordGloss.Status = p.map { $0.correct > 0 || $0.isLearned ? .known : .met } ?? .new
            out.append(WordGloss(text: t, meaning: vocab.shortMeaning(e), status: status, entryId: e.id))
        }
        return out
    }
}

// MARK: - Grammar mastery

struct GrammarExample: Codable, Hashable {
    let ja: String
    let en: String
    let videoId: String
    let title: String
}

struct GrammarProgress: Codable, Identifiable {
    let id: String
    var firstSeen = Date()
    var lastSeen = Date()
    var correct = 0
    var wrong = 0
    var stability = Memory.firstStability
    var lastReview = Date()
    var due = Date()
    var lapses = 0
    var examples: [GrammarExample] = []

    var isDue: Bool { due <= Date() }
    /// Right twice and it lasts a day or more.
    var isSolid: Bool { correct >= 2 && stability >= 1 }
    var status: String { isSolid && !isDue ? "known" : isDue ? "due" : "learning" }
}

/// How a grammar card asks, from how well the learner knows the point.
enum GrammarMode: String, Codable {
    /// First meeting: the piece is highlighted and explained, then a guided pick.
    case notice
    /// Fill the blank in the Short's line.
    case cloze
    /// Build the chunk (word + piece + next word) from tiles, with one wrong tile.
    case build
}

@MainActor
final class GrammarBook: ObservableObject {
    static let shared = GrammarBook()
    @Published private(set) var points: [String: GrammarProgress] = [:]

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("grammar.json")
    }()

    private init() {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode([String: GrammarProgress].self, from: d) { points = p }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetJourney") { points = [:]; save() }
        #endif
    }

    func progress(_ id: String) -> GrammarProgress? { points[id] }

    func solidCount(tier: Int) -> Int {
        points.values.filter { $0.isSolid && (GrammarCatalog.byId[$0.id]?.tier ?? 0) >= tier }.count
    }

    /// Short labels of points the learner has right at least once (sent to Jev as "already knows").
    var knownTitles: [String] {
        points.values.filter { $0.correct > 0 }.sorted { GrammarCatalog.order($0.id) < GrammarCatalog.order($1.id) }
            .compactMap { GrammarCatalog.byId[$0.id].map { "\($0.title) (\($0.meaning))" } }
    }

    /// Which points may be asked now: due or still learning ones, plus at most the next two new ones in ladder order.
    func eligible(maxTier: Int) -> Set<String> {
        var out = Set<String>()
        var newAllowed = 2
        for p in GrammarCatalog.points where p.tier <= maxTier {
            if let g = points[p.id] {
                if g.isDue || !g.isSolid { out.insert(p.id) }
            } else if newAllowed > 0 {
                out.insert(p.id)
                newAllowed -= 1
            }
        }
        return out
    }

    func status(_ id: String) -> String { points[id]?.status ?? "new" }

    func mode(for id: String, canBuild: Bool) -> GrammarMode {
        guard let g = points[id] else { return .notice }
        guard g.correct > 0 else { return .cloze }
        return canBuild && g.correct >= 2 && g.correct % 2 == 0 ? .build : .cloze
    }

    func record(_ id: String, correct: Bool, guided: Bool, example: GrammarExample?) {
        var g = points[id] ?? GrammarProgress(id: id)
        let now = Date()
        let elapsed = now.timeIntervalSince(g.lastReview) / 86400
        if correct {
            // A guided answer (the piece was just shown) is a first meeting, not proof of recall.
            if !guided {
                g.correct += 1
                g.stability = Memory.next(stability: g.stability, elapsedDays: elapsed, grade: .good, lapses: g.lapses)
            }
        } else {
            g.wrong += 1
            if g.correct > 0 { g.lapses += 1 }
            g.stability = Memory.next(stability: g.stability, elapsedDays: elapsed, grade: .again, lapses: g.lapses)
        }
        g.lastReview = now
        g.lastSeen = now
        g.due = now.addingTimeInterval(g.stability * 86400)
        if let example, !g.examples.contains(where: { $0.ja == example.ja }) {
            g.examples.insert(example, at: 0)
            g.examples = Array(g.examples.prefix(6))
        }
        points[id] = g
        save()
    }

    func reset() { points = [:]; save() }

    private func save() {
        if let d = try? JSONEncoder().encode(points) { try? d.write(to: url, options: .atomic) }
    }
}
