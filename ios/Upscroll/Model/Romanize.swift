import Foundation

/// Romaji for any Japanese line, kanji included, using the system's Japanese tokenizer (on-device).
enum Romanize {
    static func isJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    static func line(_ text: String) -> String {
        let cf = text as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cf))
        guard let tok = CFStringTokenizerCreate(nil, cf, range, kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale) else { return "" }
        var parts: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tok) != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tok, kCFStringTokenizerAttributeLatinTranscription) as? String {
                parts.append(latin)
            } else {
                let r = CFStringTokenizerGetCurrentTokenRange(tok)
                if let sub = CFStringCreateWithSubstring(nil, cf, r) as String?, !sub.trimmingCharacters(in: .whitespaces).isEmpty {
                    parts.append(sub)
                }
            }
        }
        return parts.joined(separator: " ")
    }

    /// The tokenizer writes a split-off small っ as "~tsu" (待って → "ma~tsu te"): double the next consonant
    /// instead ("matte"), and drop it where nothing follows (えっ → "e").
    static func smallTsu(_ s: String) -> String {
        s.replacingOccurrences(of: "~tsu\\s*([bcdfghjkmnprstvwz])", with: "$1$1", options: .regularExpression)
            .replacingOccurrences(of: "~tsu", with: "")
    }

    /// Display romaji spelled the way it's said: particles は/へ/を → wa/e/o, こんにちは → konnichiwa,
    /// no stray apostrophes ("kon'nichi" → "konnichi"). For showing to learners; matching uses SpeechCheck.romaji.
    static func pronounced(_ text: String) -> String {
        let cf = text as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cf))
        guard let tok = CFStringTokenizerCreate(nil, cf, range, kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale) else { return text }
        var out = ""
        // Lines written without spaces (real captions): space every word, but keep verb endings attached.
        let spaced = text.contains(" ") || text.contains("　")
        let endings = ["ます", "ませ", "まし", "ん", "です", "でし", "た", "ない", "なかっ", "う", "よう", "たい", "てる", "ちゃう"]
        var prevEnd = 0
        var forceSpace = false
        var glueNext = false
        while CFStringTokenizerAdvanceToNextToken(tok) != [] {
            let r = CFStringTokenizerGetCurrentTokenRange(tok)
            // Space only where the source had one (or around particles), so words aren't chopped into syllables.
            let gap = r.location > prevEnd ? ((CFStringCreateWithSubstring(nil, cf, CFRange(location: prevEnd, length: r.location - prevEnd)) as String?) ?? "") : ""
            let sourceSpace = gap.contains(" ") || gap.contains("　")
            prevEnd = r.location + r.length
            let surface = (CFStringCreateWithSubstring(nil, cf, r) as String?) ?? ""
            if surface.trimmingCharacters(in: .whitespaces).isEmpty { forceSpace = true; continue }
            var latin: String
            switch surface {
            case "は": latin = "wa"
            case "へ": latin = "e"
            case "を": latin = "o"
            default:
                latin = (CFStringTokenizerCopyCurrentTokenAttribute(tok, kCFStringTokenizerAttributeLatinTranscription) as? String) ?? surface
                if ["こんにちは", "こんばんは", "今日は", "今晩は"].contains(surface), latin.hasSuffix("ha") {
                    latin = String(latin.dropLast(2)) + "wa"
                }
            }
            latin = latin.lowercased()   // keep macrons (kōhī): long vowels matter for pronunciation
            latin = latin.replacingOccurrences(of: "n'(?=[^aeiouy])", with: "n", options: .regularExpression)
            // Japanese punctuation → ASCII, attached to the previous word.
            let punct: [String: String] = ["。": ".", "、": ",", "！": "!", "？": "?", "!": "!", "?": "?", "…": "…"]
            if let p = punct[surface] { out += p; forceSpace = true; continue }
            // Particles stand apart so learners can see the pieces ("koko ni konbini ga arimasu").
            let particle = ["は", "へ", "を", "が", "に", "で", "と", "も", "の", "か", "ね", "よ", "から", "まで", "です", "でした", "でしょう"].contains(surface)
            let space = !out.isEmpty && !glueNext && (sourceSpace || forceSpace || particle || (!spaced && !endings.contains(surface)))
            out += (space ? " " : "") + latin
            forceSpace = particle
            glueNext = surface == "お" || surface == "ご"   // honorific prefix stays on its word: onegai, gohan
        }
        return smallTsu(out)
    }
}
