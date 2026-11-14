// Fills empty "romaji" fields in vocab.json using the same transform as the app's Kana.romaji.
import Foundation

let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
var entries = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

func romaji(_ kana: String, verb: Bool) -> String {
    let hira = kana.applyingTransform(.hiraganaToKatakana, reverse: true) ?? kana
    var r = hira.applyingTransform(.latinToHiragana, reverse: true) ?? hira
    // Long vowels the way beginners read them: ō / ū, and drop the ICU apostrophes ("n'" → "n").
    // Hepburn spellings for づ/ぢ.
    for (a, b) in [("dzu", "zu"), ("dji", "ji")] { r = r.replacingOccurrences(of: a, with: b) }
    // A verb's final う is its own sound: 思う is "omou", not "omō".
    for (a, b) in [("ou", "ō"), ("oo", "ō"), ("uu", "ū")] {
        r = r.replacingOccurrences(of: a + (verb ? "(?=.)" : ""), with: b, options: .regularExpression)
    }
    r = r.replacingOccurrences(of: "~", with: "-")
    return r.replacingOccurrences(of: "'", with: "")
}

for i in entries.indices where (entries[i]["romaji"] as? String ?? "").isEmpty {
    entries[i]["romaji"] = romaji(entries[i]["kana"] as! String, verb: entries[i]["pos"] as? String == "verb")
}
let out = try JSONSerialization.data(withJSONObject: entries, options: [.withoutEscapingSlashes])
try out.write(to: URL(fileURLWithPath: path))
