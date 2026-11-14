import Foundation

/// A short beginner example that always contains the word, for when the video's translated line doesn't.
/// Hand-written for common function words; simple safe patterns for nouns, い-adjectives and verbs.
enum SimpleExample {
    struct Example { let ja: String; let romaji: String; let en: String }

    private static let curated: [String: (String, String)] = [
        "だれか": ("だれか いますか？", "Is someone there?"),
        "だれ": ("あの ひとは だれ？", "Who is that person?"),
        "まえ": ("えきの まえで あおう。", "Let's meet in front of the station."),
        "うしろ": ("うしろを みて！", "Look behind you!"),
        "なに": ("これは なに？", "What is this?"),
        "どこ": ("トイレは どこ？", "Where is the toilet?"),
        "いつ": ("いつ いく？", "When are you going?"),
        "なぜ": ("なぜ わらってるの？", "Why are you laughing?"),
        "どう": ("どう おもう？", "What do you think?"),
        "いま": ("いま なんじ？", "What time is it now?"),
        "きょう": ("きょうは あついね。", "It's hot today."),
        "あした": ("また あした！", "See you tomorrow!"),
        "きのう": ("きのう えいがを みた。", "I watched a movie yesterday."),
        "もっと": ("もっと ほしい！", "I want more!"),
        "ぜんぶ": ("ぜんぶ たべた！", "I ate it all!"),
        "ちょっと": ("ちょっと まって！", "Wait a sec!"),
        "とても": ("とても きれい！", "Very pretty!"),
        "あなた": ("あなたは がくせい？", "Are you a student?"),
        "わたし": ("わたしは サムです。", "I'm Sam."),
        "みんな": ("みんな、ありがとう！", "Thanks, everyone!"),
        "なにか": ("なにか たべたい。", "I want to eat something."),
        "どこか": ("どこか いこう！", "Let's go somewhere!"),
        "いっしょ": ("いっしょに いこう！", "Let's go together!"),
        "ほんとう": ("ほんとう？", "Really?"),
    ]

    /// The word's own romaji (kyō) inside the example's romaji (kyou wa…), so one sheet uses one spelling.
    private static func align(_ romaji: String, _ e: VocabEntry) -> String {
        let plain = Romanize.pronounced(e.kana)
        guard !plain.isEmpty, plain != e.romaji else { return romaji }
        return romaji.replacingOccurrences(of: plain, with: e.romaji)
    }

    static func make(for e: VocabEntry) -> Example? {
        guard let ex = makeRaw(e) else { return nil }
        return Example(ja: ex.ja, romaji: align(ex.romaji, e), en: ex.en)
    }

    private static func makeRaw(_ e: VocabEntry) -> Example? {
        let k = e.kana
        let gloss = e.meaning.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? e.meaning
        if let c = curated[k] { return Example(ja: c.0, romaji: Romanize.pronounced(c.0), en: c.1) }
        let ja: String, en: String
        switch e.pos {
        case "noun":
            ja = "\(k)は どこ？"; en = "Where is the \(gloss)?"
        case "adj" where k.hasSuffix("い") && !k.hasSuffix("きれい"):
            ja = "これ、\(k)ね！"; en = "This is \(gloss), isn't it!"
        case "verb" where k.last.map { "うくぐすつぬぶむる".contains($0) } ?? false:
            let base = gloss.hasPrefix("to ") ? String(gloss.dropFirst(3)) : gloss
            ja = "いま \(k)？"; en = "Are you going to \(base) now?"
        default:
            return nil
        }
        return Example(ja: ja, romaji: Romanize.pronounced(ja), en: en)
    }
}
