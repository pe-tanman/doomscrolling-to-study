import Foundation
import NaturalLanguage

struct VocabEntry: Codable, Hashable, Identifiable {
    let id: String
    /// English lemmas/forms this entry can replace, lowercased ("tired", "cat").
    let en: [String]
    let kana: String
    let kanji: String?
    let romaji: String
    let meaning: String
    /// Katakana loanword (コーヒー for "coffee"): the easiest day-1 wins.
    let loanword: Bool
    /// Required part of speech in the English sentence: noun, verb, adj, adv, pron, num, any.
    let pos: String
    let emoji: String
    /// JLPT level: 5 = N5 (first words) … 1 = N1. Word lists: see tools/data/jlpt/SOURCE.md.
    var level: Int = 5

    var levelName: String { "N\(level)" }

    /// ～ご, ～えん, ～さん…: attaches to another word, never stands alone.
    var isSuffix: Bool { kana.hasPrefix("～") || kana.hasPrefix("〜") }

    /// Beginner note for suffixes, with a real combined example.
    var suffixNote: String? {
        guard isSuffix else { return nil }
        let examples: [String: String] = [
            "～ご": "にほん + ご = にほんご (Japanese language). Not \"word\" in general.",
            "～えん": "ひゃく + えん = ひゃくえん (100 yen).",
            "～さん": "たなか + さん = たなかさん (Mr./Ms. Tanaka).",
            "～じ": "さん + じ = さんじ (3 o'clock).",
            "～かげつ": "いっ + かげつ = いっかげつ (one month).",
            "～さい": "はたち / にじゅっさい (20 years old).",
            "～がつ": "し + がつ = しがつ (April).",
            "～じん": "にほん + じん = にほんじん (a Japanese person).",
        ]
        let key = examples.keys.first { kana.hasPrefix($0) }
        return "～ means it attaches to the end of another word. " + (key.flatMap { examples[$0] } ?? "It isn't used on its own.")
    }

    /// Some entries list alternative readings ("まいげつ; まいつき"). Sentences and cards use the first one.
    var mainKana: String { kana.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? kana }
    var mainRomaji: String { romaji.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? romaji }
    /// The other readings, shown separately after the reveal ("also: まいつき").
    var otherKana: [String] { kana.split(separator: ";").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) } }

    /// The most "written" form: kanji if there is one, else kana.
    var written: String { kanji ?? mainKana }
}

/// Script ladder from the plan: L0 romaji + audio, L1 kana + romaji, L2 kana only, L3 kanji + furigana.
/// How Japanese words are written in subtitles, cards and answer options.
/// There is no romaji-only level: even brand-new learners see real kana, with the romaji sound as a helper,
/// so every word they meet also teaches the letters. (Raw value 0 was "romaji only"; old saves load as kana + romaji.)
enum ScriptLevel: Int, CaseIterable, Codable, Identifiable {
    case kanaRomaji = 1, kana, kanji

    var id: Int { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = ScriptLevel(rawValue: raw) ?? .kanaRomaji
    }

    var label: String {
        switch self {
        case .kanaRomaji: return "L1 · Kana + romaji"
        case .kana: return "L2 · Kana"
        case .kanji: return "L3 · Kanji + furigana"
        }
    }

    /// One plain-language line for beginners (no jargon like "L1").
    var explanation: String {
        switch self {
        case .kanaRomaji: return "Japanese letters (kana) with the sound in English letters above. Best for beginners."
        case .kana: return "Japanese letters only, once you can read kana."
        case .kanji: return "Real written Japanese with reading hints."
        }
    }

    /// `main` is the big form; `sub` is the small helper shown above it.
    func display(_ e: VocabEntry) -> (main: String, sub: String?) {
        switch self {
        case .kanaRomaji: return (e.mainKana, e.mainRomaji)
        case .kana: return (e.mainKana, nil)
        case .kanji: return (e.kanji ?? e.mainKana, e.kanji == nil ? nil : e.mainKana)
        }
    }
}

/// A word in a cue that we will swap.
struct SwapMatch: Hashable {
    let entry: VocabEntry
    /// Range of the original English word within the cue text.
    let range: Range<String.Index>
}

final class VocabStore {
    let entries: [VocabEntry]
    let byId: [String: VocabEntry]
    private let byForm: [String: VocabEntry]
    /// Every entry for an English form, in list order ("poor" → へた, かわいそう, にがて, まずしい, ひんじゃく).
    private let byFormAll: [String: [VocabEntry]]
    /// English forms with clearly different meanings in Japanese ("poor baby" かわいそう ≠ "poor family" まずしい ≠
    /// "poor at math" へた). The phone never swaps these on its own: only after Jev confirms which sense the line uses.
    let polysemous: Set<String>
    /// Japanese spelling (kanji or kana) → entry, easiest level first. Used to gloss words in a Japanese line.
    let byJapanese: [String: VocabEntry]

    /// Beginner-friendly meaning for answer choices: no dictionary jargon ("-- honorific form for 人 --"),
    /// no truncation marks, first sense only. "person (polite form)" instead of "-- honorific form for 人 --, way of…".
    func shortMeaning(_ e: VocabEntry) -> String {
        var m = e.meaning
        var register: String?
        if let r = m.range(of: "--.*?(--|$)", options: .regularExpression) {
            let note = String(m[r])
            if note.contains("honorific") || note.contains("polite") { register = "polite form" }
            else if note.contains("humble") || note.contains("modest") { register = "humble form" }
            // The note names the plain word in Japanese ("for 人", "for いく"): use that word's own meaning.
            // First Japanese word named in the note ("for いく, くる" → いく).
            let isJP: (Character) -> Bool = { c in c.unicodeScalars.allSatisfy { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) } }
            let key = String(note.drop(while: { !isJP($0) }).prefix(while: isJP))
            let common = ["する": "to do", "いる": "to be (somewhere)", "いく": "to go", "くる": "to come", "たべる": "to eat",
                          "食べる": "to eat", "飲む": "to drink", "言う": "to say", "いう": "to say", "もらう": "to receive",
                          "あげる": "to give", "人": "person", "家": "house", "ください": "please give me", "みる": "to see"]
            let baseMeaning = common[key] ?? (key.isEmpty ? nil : entries.first { $0.kanji == key || $0.kana == key }?.meaning)
            m.removeSubrange(r)
            m = m.trimmingCharacters(in: CharacterSet(charactersIn: " ,;…"))
            if m.isEmpty || m.hasPrefix("way of") {
                if let b = baseMeaning { m = b }
                else if note.contains("greeting") { m = "formal greeting (letters)" }
            }
        }
        m = m.replacingOccurrences(of: "…", with: "")
        var first = m.split(whereSeparator: { $0 == ";" }).first.map(String.init) ?? m
        first = first.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        if first.count > 28, let cut = first.prefix(28).lastIndex(of: ",") { first = String(first[..<cut]) }
        if first.isEmpty || first.hasPrefix("--") { first = register == nil ? "set expression" : "special verb" }
        return register.map { "\(first) (\($0))" } ?? first
    }

    /// Entry for an English form ("dog", "ice cream").
    func entry(forForm form: String) -> VocabEntry? { byForm[form.lowercased()] }

    /// Words per JLPT level (5 = N5 … 1 = N1).
    let countByLevel: [Int: Int]

    convenience init(resource: String = "vocab") {
        let url = Bundle.main.url(forResource: resource, withExtension: "json")
        self.init(data: url.flatMap { try? Data(contentsOf: $0) } ?? Data("[]".utf8))
    }

    init(data: Data) {
        entries = (try? JSONDecoder().decode([VocabEntry].self, from: data)) ?? []
        var forms: [String: VocabEntry] = [:]
        var all: [String: [VocabEntry]] = [:]
        for e in entries { for w in e.en { if forms[w] == nil { forms[w] = e }; all[w, default: []].append(e) } }
        byForm = forms
        byFormAll = all
        polysemous = Self.findPolysemous(all)
        byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ja: [String: VocabEntry] = [:]
        for e in entries.sorted(by: { $0.level > $1.level }) where !e.isSuffix {
            for f in [e.kanji, e.kana].compactMap({ $0 }) where !f.isEmpty && ja[f] == nil { ja[f] = e }
        }
        byJapanese = ja
        countByLevel = Dictionary(grouping: entries, by: \.level).mapValues(\.count)
    }

    /// A form is polysemous when two of its entries have other glosses that share nothing:
    /// へた {unskillful} vs まずしい {needy} → different senses; いえ {home} vs うち {home} → synonyms.
    static func findPolysemous(_ all: [String: [VocabEntry]]) -> Set<String> {
        var out = Set<String>()
        for (w, es) in all where es.count > 1 {
            let others = es.map { Set($0.en).subtracting([w]) }.filter { !$0.isEmpty }
            outer: for i in others.indices { for j in others.indices where j > i && others[i].isDisjoint(with: others[j]) { out.insert(w); break outer } }
        }
        return out
    }

    /// Candidate swaps in an English cue: lemmatize with NLTagger, look up each lemma,
    /// and require the part of speech to match ("like" the verb, not "like this").
    /// `upTo`: the learner's JLPT level; harder words (lower N number… i.e. N3 when at N4) are skipped.
    /// - allSenses false (the phone choosing words on its own): words with several meanings are skipped,
    ///   so "poor baby" never becomes まずしい / へた.
    /// - allSenses true: every sense is returned (for Jev to judge, and to find an already-approved swap again).
    func candidates(in text: String, upTo level: Int = 1, allSenses: Bool = false) -> [SwapMatch] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        var found: [SwapMatch] = []
        var used = Set<String>()
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let surface = text[range].lowercased()
            let lemma = tag?.rawValue.lowercased() ?? surface
            // Suffixes (～ご "language", ～えん "yen") attach to Japanese words; dropping them alone into English misleads.
            // One-kana words (え, き, て…) are ambiguous on their own; never swap them in.
            let form = byFormAll[lemma] != nil ? lemma : surface
            guard let senses = byFormAll[form] else { return true }
            if !allSenses && (polysemous.contains(form) || Self.inSetPhrase(text, range)) { return true }
            let (lex, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
            for e in (allSenses ? senses : [byForm[form]!]) {
                guard e.level >= level, !used.contains(e.id), !e.isSuffix, e.kana.count >= 2 else { continue }
                var fits = e.pos == "question" ? Self.isQuestionUse(text, range) : Self.posMatches(e.pos, lex)
                // "which team", "this car", "what color": English uses these before a noun, Japanese needs どの/この/なんの.
                // Swapping in どれ/これ/なに there would teach the wrong pattern, so skip determiner uses.
                if fits, Self.pronounOnly.contains(e.kana), Self.nextWordIsNounLike(tagger, text, after: range) { fits = false }
                if fits {
                    found.append(SwapMatch(entry: e, range: range))
                    used.insert(e.id)
                }
            }
            return true
        }
        return found
    }

    /// English set phrases whose words don't map one-to-one onto Japanese ("good morning" is おはよう, not いい + あさ).
    /// A word inside one is never swapped by the phone (Jev still judges it when online).
    static let setPhrases: [String] = [
        "good morning", "good night", "good luck", "good job", "good for you", "good to go", "for good", "my bad", "too bad", "not bad",
        "i'm good", "im good", "all good", "make sense", "makes sense", "made sense", "take care", "take a break", "take place",
        "take it easy", "what's up", "whats up", "never mind", "of course", "kind of", "sort of", "a lot", "at least", "at all",
        "come on", "hang out", "give up", "figure out", "break a leg", "piece of cake", "no way", "by the way", "right now",
        "all right", "you know", "i mean", "oh my god", "oh my gosh", "big deal", "hold on", "go ahead", "let's go", "get it",
        "poor thing", "poor baby", "dead tired", "cold feet", "hot take", "on fire", "in time", "on time", "so far", "as well",
    ]

    static func inSetPhrase(_ text: String, _ range: Range<String.Index>) -> Bool {
        let lower = text.lowercased()
        let at = text.distance(from: text.startIndex, to: range.lowerBound)
        for p in setPhrases {
            var from = lower.startIndex
            while let r = lower.range(of: p, range: from..<lower.endIndex) {
                // whole words only ("a lot" must not match "a lottery")
                let before = r.lowerBound == lower.startIndex || !lower[lower.index(before: r.lowerBound)].isLetter
                let after = r.upperBound == lower.endIndex || !lower[r.upperBound].isLetter
                let lo = lower.distance(from: lower.startIndex, to: r.lowerBound), hi = lower.distance(from: lower.startIndex, to: r.upperBound)
                if before && after && at >= lo && at < hi { return true }
                from = r.upperBound
            }
        }
        return false
    }

    /// Japanese words that stand alone (pronouns), never directly before a noun.
    static let pronounOnly: Set<String> = ["これ", "それ", "あれ", "どれ", "なに", "だれ"]

    static func nextWordIsNounLike(_ tagger: NLTagger, _ text: String, after range: Range<String.Index>) -> Bool {
        var result = false
        tagger.enumerateTags(in: range.upperBound..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace]) { tag, _ in
            result = tag == .noun || tag == .adjective || tag == .number
            return false   // only the very next token
        }
        return result
    }

    /// Question words (なに, だれ, どこ, なんで, いつ, どう, どれ) only when the clause really asks something:
    /// "What color is it?" / "what's that" → yes; "look what I built", "tell me what it is",
    /// "when I was young" → no (relative/embedded use; Japanese says these differently).
    static func isQuestionUse(_ text: String, _ range: Range<String.Index>) -> Bool {
        let enders: Set<Character> = [".", "!", "?", "\n"]
        // Start of the sentence that contains the word.
        var start = text.startIndex
        if let i = text[..<range.lowerBound].lastIndex(where: { enders.contains($0) }) { start = text.index(after: i) }
        let before = text[start..<range.lowerBound]
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“‘>-–—(")))
            .lowercased()
        // Clause-initial: nothing before it, or only a comma-separated lead-in ("Okay, what…", "So what…").
        let leadIns: Set<String> = ["so", "and", "but", "okay", "ok", "wait", "like", "um", "uh", "oh", "then", "well", "hey"]
        let clauseStart = before.isEmpty || before.hasSuffix(",") || leadIns.contains(before)
        guard clauseStart else { return false }

        // End of the sentence: an explicit "?" settles it.
        let rest = text[range.upperBound...]
        let end = rest.firstIndex(where: { enders.contains($0) })
        if let end, rest[end] == "?" { return true }

        // Auto-captions often have no "?": accept a question-shaped start ("what is", "why did", "who's").
        let after = rest.prefix(while: { $0 != "\n" }).lowercased()
        if after.hasPrefix("'s") || after.hasPrefix("’s") || after.hasPrefix("'re") || after.hasPrefix("’re") { return true }
        let next = after.split(whereSeparator: { !$0.isLetter && $0 != "'" }).first.map(String.init) ?? ""
        let aux: Set<String> = ["is", "are", "was", "were", "do", "does", "did", "can", "could", "will", "would",
                                "should", "am", "have", "has", "happened", "happens", "kind", "color", "time"]
        return aux.contains(next)
    }

    private static func posMatches(_ pos: String, _ tag: NLTag?) -> Bool {
        guard let tag else { return pos == "any" }
        switch pos {
        case "noun": return tag == .noun
        case "verb": return tag == .verb
        case "adj": return tag == .adjective
        case "adv": return tag == .adverb
        case "pron": return tag == .pronoun
        case "num": return tag == .number
        default: return true
        }
    }

    /// Distractors for a quiz: other entries with a different meaning, same level and part of speech first
    /// (a beginner shouldn't be choosing between いぬ and an N1 word).
    /// Distractors that fit the same slot in a sentence: the こ/そ/あ/ど family, or words of the same
    /// part of speech with the same ending (い-adjectives, う-verbs), so only knowing the word helps.
    /// Words that share an English meaning ("easy": やさしい, かんたん, ようい…) are equally right answers.
    /// They are never offered as wrong options, and speaking accepts any of them.
    func equivalent(_ a: VocabEntry, _ b: VocabEntry) -> Bool {
        a.id == b.id || a.kana == b.kana || !Set(a.en).isDisjoint(with: b.en)
    }

    /// Other words for the same meaning as `e` (for accepting them as answers).
    func equivalents(of e: VocabEntry) -> [VocabEntry] {
        var seen = Set([e.id]), out: [VocabEntry] = []
        for w in e.en { for o in byFormAll[w] ?? [] where !o.isSuffix && seen.insert(o.id).inserted { out.append(o) } }
        return out
    }

    /// "starts with や" when the meaning has other Japanese words, so a spelling prompt says which one it wants.
    func whichWordHint(for e: VocabEntry) -> String? {
        guard !equivalents(of: e).isEmpty, let first = e.mainKana.first else { return nil }
        return "the word starting with \(first)"
    }

    func sameShapeDistractors(for e: VocabEntry, count: Int) -> [VocabEntry] {
        let families: [[String]] = [["こんな", "そんな", "あんな", "どんな"], ["この", "その", "あの", "どの"],
                                    ["ここ", "そこ", "あそこ", "どこ"], ["これ", "それ", "あれ", "どれ"],
                                    ["こう", "そう", "ああ", "どう"]]
        if let fam = families.first(where: { $0.contains(e.kana) }) {
            let picks = fam.filter { $0 != e.kana }.compactMap { k in entries.first { $0.kana == k } }.filter { !equivalent($0, e) }
            if picks.count >= count { return Array(picks.shuffled().prefix(count)) }
        }
        let last = e.kana.last
        let same = entries.filter { o in
            !equivalent(o, e) && o.meaning != e.meaning && !o.isSuffix && abs(o.level - e.level) <= 1
                && o.pos == e.pos && o.kana.last == last && o.loanword == e.loanword
        }.shuffled()
        let picked = Array(same.prefix(count))
        return picked.count >= count ? picked : picked + distractors(for: e, count: count - picked.count)
    }

    /// Meaning-question distractors that could plausibly fit: same kind of word (verb vs not, by POS or a
    /// "to …" meaning), same loanword-ness, nearby level. Avoids "factory / airport / straight" for まっすぐ.
    func plausibleDistractors(for e: VocabEntry, count: Int) -> [VocabEntry] {
        let isVerb = { (x: VocabEntry) in x.pos == "verb" || x.meaning.hasPrefix("to ") }
        let kind = { (x: VocabEntry) -> String in x.pos != "any" ? x.pos : (isVerb(x) ? "verb" : "other") }
        let pool = entries.filter { o in
            !equivalent(o, e) && o.meaning != e.meaning && !o.isSuffix && !o.meaning.contains("--")
                && abs(o.level - e.level) <= 1 && kind(o) == kind(e) && o.loanword == e.loanword
        }.shuffled()
        let picked = Array(pool.prefix(count))
        return picked.count >= count ? picked : picked + distractors(for: e, count: count - picked.count)
    }

    func distractors(for e: VocabEntry, count: Int) -> [VocabEntry] {
        let ok = { (o: VocabEntry) in !self.equivalent(o, e) && o.meaning != e.meaning }
        let near = { (o: VocabEntry) in abs(o.level - e.level) <= 1 }
        let tiers: [[VocabEntry]] = [
            entries.filter { ok($0) && near($0) && $0.pos == e.pos }.shuffled(),
            entries.filter { ok($0) && near($0) && $0.pos != e.pos }.shuffled(),
            entries.filter { ok($0) && !near($0) }.shuffled(),
        ]
        return Array(tiers.joined().prefix(count))
    }

    /// Find this entry inside a Japanese sentence (to highlight it in the translated line).
    static func range(of e: VocabEntry, inJapanese text: String) -> Range<String.Index>? {
        var forms = [e.kanji, e.kana].compactMap { $0 }
        // Conjugated verbs/adjectives: also try the stem (食べる → 食べ, 楽しい → 楽し).
        for f in [e.kanji, e.kana].compactMap({ $0 }) where f.count >= 2 {
            if let last = f.last, "うくぐすつぬぶむるい".contains(last) { forms.append(String(f.dropLast())) }
        }
        for f in forms where !f.isEmpty {
            if let r = text.range(of: f) { return r }
        }
        return nil
    }
}

/// JLPT levels, easiest first. 5 = N5 … 1 = N1.
enum JLPT {
    static let levels = [5, 4, 3, 2, 1]
    static func title(_ level: Int) -> String {
        switch level {
        case 5: return "First words"
        case 4: return "Everyday basics"
        case 3: return "Intermediate"
        case 2: return "Upper intermediate"
        default: return "Advanced"
        }
    }
    /// Plain-language description; JLPT is the standard Japanese test, N5 the easiest.
    static func explanation(_ level: Int) -> String {
        switch level {
        case 5: return "N5 is the easiest level: about 700 first words like big, good and eat. Start here if you're new."
        case 4: return "N4: everyday basics, for after you know most first words."
        case 3: return "N3: intermediate words for daily conversation."
        case 2: return "N2: upper intermediate, news and work."
        default: return "N1: advanced, near-native vocabulary."
        }
    }
    /// Suggest the next level once this share of the current level is learned.
    static let levelUpShare = 0.4
}
