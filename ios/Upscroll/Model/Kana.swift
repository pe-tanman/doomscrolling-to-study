import Foundation

/// One sound unit (mora) of a kana word: な, きゃ, っ, ー …
struct KanaUnit: Hashable, Identifiable {
    let kana: String
    let romaji: String
    /// Short teaching note for the special marks (っ, ー).
    let note: String?
    var id: String { kana + romaji }
}

/// Splits kana into sound units with romaji, so learners pick up the kana chart
/// from words they already met in their feed.
enum Kana {
    private static let smallCombiners: Set<Character> = ["ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ャ", "ュ", "ョ", "ァ", "ィ", "ゥ", "ェ", "ォ"]

    static func units(_ word: String) -> [KanaUnit] {
        var out: [KanaUnit] = []
        for ch in word {
            let c = String(ch)
            if smallCombiners.contains(ch), let last = out.last, last.note == nil {
                let combined = last.kana + c
                out[out.count - 1] = KanaUnit(kana: combined, romaji: romaji(combined), note: nil)
            } else if c == "っ" || c == "ッ" {
                out.append(KanaUnit(kana: c, romaji: "·", note: "small tsu: a tiny pause, doubles the next sound"))
            } else if c == "ー" {
                out.append(KanaUnit(kana: c, romaji: "—", note: "long mark: stretch the vowel before it"))
            } else if isKana(ch) {
                out.append(KanaUnit(kana: c, romaji: romaji(c), note: nil))
            }
        }
        return out
    }

    static func romaji(_ kana: String) -> String {
        let hira = kana.applyingTransform(.hiraganaToKatakana, reverse: true) ?? kana
        return hira.applyingTransform(.latinToHiragana, reverse: true) ?? kana
    }

    static func isKana(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || (0x30A1...0x30FA).contains($0.value) }
    }

    static func isKatakana(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x30A1...0x30FA).contains($0.value) }
    }

    /// A pool of basic hiragana sounds for quiz distractors.
    /// A single kana as a card entry (hiragana listening drill for learners with no words yet).
    /// Not part of the word list, so it never enters the word book.
    static func drillEntry(_ k: String) -> VocabEntry {
        let r = romaji(k)
        return VocabEntry(id: "kana:" + k, en: [], kana: k, kanji: nil, romaji: r,
                          meaning: "the sound \u{201C}\(r)\u{201D}", loanword: false, pos: "kana", emoji: "👂")
    }

    /// Three kana for a drill: the answer plus two with the same vowel (か・さ・た), so the ear has to catch the consonant.
    static func drillOptions(for k: String) -> [String] {
        let vowel = romaji(k).last
        let pool = basicHiragana.filter { $0 != k && $0 != "ん" && $0 != "を" && romaji($0).last == vowel }.shuffled()
        let others = pool.count >= 2 ? Array(pool.prefix(2))
                                      : Array(basicHiragana.filter { $0 != k }.shuffled().prefix(2))
        return (others + [k]).shuffled()
    }

    static let basicHiragana: [String] = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん").map(String.init)

    /// Kana tiles for spelling a word: its sound units plus look-alike extras with the same vowels
    /// (か・さ・た), so the ear and eye have to catch the consonant, not just count tiles.
    static func spellTiles(for kana: String, extra: Int) -> (answer: [String], tiles: [String])? {
        let answer = Kana.units(kana).map(\.kana)
        guard (2...7).contains(answer.count), answer.joined() == kana else { return nil }
        let katakana = Kana.isKatakana(kana)
        func script(_ k: String) -> String { katakana ? (k.applyingTransform(.hiraganaToKatakana, reverse: false) ?? k) : k }
        let vowels = Set(answer.compactMap { Kana.romaji($0).last })
        let base = Kana.basicHiragana.filter { $0 != "を" && $0 != "ん" }.map { (k: $0, shown: script($0)) }
            .filter { !answer.contains($0.shown) }
        let similar = base.filter { Kana.romaji($0.k).last.map(vowels.contains) ?? false }.shuffled()
        var extras = Array(similar.prefix(extra)).map(\.shown)
        if extras.count < extra { extras += base.filter { !extras.contains($0.shown) }.shuffled().prefix(extra - extras.count).map(\.shown) }
        return (answer, (answer + extras).shuffled())
    }
}
