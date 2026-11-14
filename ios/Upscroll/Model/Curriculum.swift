import Foundation

/// The Tokyo journey (curriculum v2): 7 places, each a set of phrases with the grammar inside them.
/// No lesson order: every phrase has a 4-skill coverage ring that fills while you scroll.
struct Phrase: Identifiable, Hashable {
    let id: String
    /// How it's shown in lists ("〜を ください").
    let pattern: String
    let meaning: String
    /// A concrete example to hear, build and say.
    let example: String
    let exampleKana: String
    let exampleEnglish: String
    /// Builder tiles for the example, in order.
    let tiles: [String]
    /// Strings that mean this phrase appears in a Japanese caption line (kana and kanji forms).
    let matches: [String]
    let grammar: String

    func appears(in line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        return matches.contains { compact.contains($0) }
    }
}

/// A real-world thing you can do; becomes a passport stamp when all its phrases are fully covered.
struct CanDo: Identifiable, Hashable {
    let id: String
    let title: String
    let stamp: String      // kanji on the stamp, e.g. 注文
    let phraseIds: [String]
}

struct Place: Identifiable, Hashable {
    let id: String
    let index: Int
    let name: String
    let japanese: String
    let level: String
    let summary: String
    let scene: String       // asset name
    let souvenir: String    // asset name
    let souvenirName: String
    /// Cumulative words-learned target by the end of this place.
    let wordsTarget: Int
    let phrases: [Phrase]
    let canDos: [CanDo]
    let grammar: [String]
    /// Position of the pin on the world map (fractions of the map image).
    let pin: (x: Double, y: Double)

    static func == (a: Place, b: Place) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum Curriculum {
    private static func p(_ id: String, _ pattern: String, _ meaning: String, _ example: String, _ kana: String, _ en: String,
                          _ tiles: [String], _ matches: [String], _ grammar: String) -> Phrase {
        Phrase(id: id, pattern: pattern, meaning: meaning, example: example, exampleKana: kana, exampleEnglish: en,
               tiles: tiles, matches: matches, grammar: grammar)
    }

    static let places: [Place] = [
        Place(id: "arrival", index: 0, name: "Arrival", japanese: "くうこう", level: "Pre-N5",
              summary: "Hear and read every かな; react to a Short.", scene: "scene_airport",
              souvenir: "souvenir_tag", souvenirName: "Luggage tag", wordsTarget: 60,
              phrases: [
                p("hello", "こんにちは", "hello", "こんにちは！", "こんにちは", "Hello!", ["こんにちは", "！"], ["こんにちは", "今日は"], "Greetings"),
                p("thanks", "ありがとう", "thank you", "ありがとう！", "ありがとう", "Thank you!", ["ありがとう", "！"], ["ありがとう", "有難う"], "Greetings"),
                p("sorry", "すみません", "excuse me / sorry", "すみません", "すみません", "Excuse me.", ["すみ", "ません"], ["すみません", "済みません"], "Polite set phrase"),
                p("sugoi", "すごい！", "amazing!", "すごい！", "すごい", "Amazing!", ["すごい", "！"], ["すごい", "凄い"], "い-adjective as a reaction"),
                p("kawaii", "かわいい！", "cute!", "かわいい！", "かわいい", "So cute!", ["かわいい", "！"], ["かわいい", "可愛い"], "い-adjective as a reaction"),
              ],
              canDos: [CanDo(id: "greet", title: "Said hello", stamp: "挨拶", phraseIds: ["hello", "thanks", "sorry"]),
                       CanDo(id: "react", title: "Reacted in Japanese", stamp: "反応", phraseIds: ["sugoi", "kawaii"])],
              grammar: ["Sounds & kana", "Word order by feel (Japlish subtitles)"], pin: (0.18, 0.62)),

        Place(id: "cafe", index: 1, name: "Café", japanese: "カフェ", level: "N5 · 1",
              summary: "Introduce yourself, order a drink, say what you like.", scene: "scene_cafe",
              souvenir: "souvenir_cup", souvenirName: "Sakura latte cup", wordsTarget: 180,
              phrases: [
                p("kudasai", "〜を ください", "… please (ordering)", "コーヒーを ください", "こーひーを ください", "A coffee, please.", ["コーヒー", "を", "ください"], ["ください", "下さい"], "〜を ください"),
                p("hajimemashite", "はじめまして", "nice to meet you", "はじめまして", "はじめまして", "Nice to meet you.", ["はじめ", "まして"], ["はじめまして", "初めまして"], "Set phrase"),
                p("watashiwa", "わたしは 〜です", "I am …", "わたしは がくせいです", "わたしは がくせいです", "I'm a student.", ["わたし", "は", "がくせい", "です"], ["わたしは", "私は"], "A は B です"),
                p("suki", "〜が すきです", "I like …", "ねこが すきです", "ねこが すきです", "I like cats.", ["ねこ", "が", "すき", "です"], ["すき", "好き"], "〜が すき"),
                p("nandesuka", "これは なんですか？", "what is this?", "これは なんですか？", "これは なんですか", "What is this?", ["これ", "は", "なん", "ですか"], ["なんですか", "何ですか", "なに"], "これ · question か"),
                p("oishii", "おいしい！", "tasty!", "おいしい！", "おいしい", "Delicious!", ["おいしい", "！"], ["おいしい", "美味しい"], "い-adjective"),
              ],
              canDos: [CanDo(id: "order", title: "Ordered a drink", stamp: "注文", phraseIds: ["kudasai", "oishii"]),
                       CanDo(id: "intro", title: "Introduced myself", stamp: "自己紹介", phraseIds: ["hajimemashite", "watashiwa"]),
                       CanDo(id: "like", title: "Said what I like", stamp: "好き", phraseIds: ["suki"]),
                       CanDo(id: "ask", title: "Asked what something is", stamp: "質問", phraseIds: ["nandesuka"])],
              grammar: ["A は B です", "の · これ / それ", "〜を ください"], pin: (0.48, 0.52)),

        Place(id: "station", index: 2, name: "Station", japanese: "えき", level: "N5 · 2",
              summary: "Ask the way, say where you're going and when; invite a friend.", scene: "scene_station",
              souvenir: "souvenir_ticket", souvenirName: "Train ticket", wordsTarget: 320,
              phrases: [
                p("dokodesuka", "〜は どこですか？", "where is …? (asking the way)", "えきは どこですか？", "えきは どこですか", "Where is the station?", ["えき", "は", "どこですか"], ["どこですか", "何処ですか"], "は (topic) · です"),
                p("doko", "どこに いきますか？", "where are you going?", "どこに いきますか？", "どこに いきますか", "Where are you going?", ["どこ", "に", "いきますか"], ["どこ", "何処"], "に (destination) · ます"),
                p("nanji", "なんじですか？", "what time is it?", "いま なんじですか？", "いま なんじですか", "What time is it now?", ["いま", "なんじ", "ですか"], ["なんじ", "何時"], "Time words"),
                p("masenka", "いっしょに 〜ませんか？", "shall we … together?", "いっしょに いきませんか？", "いっしょに いきませんか", "Shall we go together?", ["いっしょに", "いき", "ませんか"], ["ませんか", "いっしょに", "一緒に"], "〜ませんか (invite)"),
                // Station survival: buy a ticket, check the train.
                p("kippu", "きっぷは どこで かえますか？", "where can I buy a ticket?", "きっぷは どこで かえますか？", "きっぷは どこで かえますか", "Where can I buy a ticket?", ["きっぷ", "は", "どこで", "かえますか"], ["きっぷ", "切符"], "で (place of action) · can-do"),
                p("densha", "この でんしゃは 〜に いきますか？", "does this train go to …?", "この でんしゃは しぶやに いきますか？", "この でんしゃは しぶやに いきますか", "Does this train go to Shibuya?", ["この", "でんしゃ", "は", "しぶやに", "いきますか"], ["でんしゃ", "電車"], "この + noun · に (destination)"),
              ],
              canDos: [CanDo(id: "way", title: "Asked the way", stamp: "道", phraseIds: ["dokodesuka"]),
                       CanDo(id: "where", title: "Asked where someone is going", stamp: "行先", phraseIds: ["doko"]),
                       CanDo(id: "time", title: "Asked the time", stamp: "時間", phraseIds: ["nanji"]),
                       CanDo(id: "invite", title: "Invited a friend", stamp: "誘い", phraseIds: ["masenka"]),
                       CanDo(id: "ticket", title: "Found the ticket machine", stamp: "切符", phraseIds: ["kippu"]),
                       CanDo(id: "train", title: "Checked I'm on the right train", stamp: "電車", phraseIds: ["densha"])],
              grammar: ["ます: now / not / past", "を・に・で・へ", "〜ませんか"], pin: (0.70, 0.43)),

        Place(id: "konbini", index: 3, name: "Konbini", japanese: "コンビニ", level: "N5 · 3",
              summary: "Describe things, ask prices and count.", scene: "scene_konbini",
              souvenir: "souvenir_onigiri", souvenirName: "Onigiri friend", wordsTarget: 520,
              phrases: [
                p("ikura", "これは いくらですか？", "how much is this?", "これは いくらですか？", "これは いくらですか", "How much is this?", ["これ", "は", "いくら", "ですか"], ["いくら"], "いくら · か"),
                p("hitotsu", "ひとつ ください", "one, please", "おにぎりを ひとつ ください", "おにぎりを ひとつ ください", "One onigiri, please.", ["おにぎり", "を", "ひとつ", "ください"], ["ひとつ", "一つ", "ふたつ", "二つ"], "Counters つ"),
                p("meccha", "めっちゃ おいしい！", "so tasty!", "めっちゃ おいしい！", "めっちゃ おいしい", "So tasty!", ["めっちゃ", "おいしい"], ["めっちゃ"], "Adverb + adjective"),
                // What the clerk says to you, and the reply (the till is where beginners freeze).
                p("fukuro", "ふくろは いりますか？", "\"do you need a bag?\" (clerk) → no thanks", "いいえ、だいじょうぶです", "いいえ、だいじょうぶです", "No, I'm fine.", ["いいえ、", "だいじょうぶ", "です"], ["ふくろ", "袋", "だいじょうぶです"], "Clerk question → polite no"),
                p("atatame", "あたためますか？", "\"shall I heat it up?\" (clerk) → yes please", "はい、おねがいします", "はい、おねがいします", "Yes, please.", ["はい、", "おねがい", "します"], ["あたため", "温め", "おねがいします"], "Clerk question → polite yes"),
              ],
              canDos: [CanDo(id: "buy", title: "Bought a snack", stamp: "買物", phraseIds: ["ikura", "hitotsu"]),
                       CanDo(id: "describe", title: "Said the food is tasty", stamp: "感想", phraseIds: ["meccha"]),
                       CanDo(id: "till", title: "Answered the clerk at the till", stamp: "会計", phraseIds: ["fukuro", "atatame"])],
              grammar: ["い adjectives", "はい / いいえ replies", "Counters つ・人・本"], pin: (0.24, 0.40)),

        Place(id: "shrine", index: 4, name: "Shrine festival", japanese: "まつり", level: "N4 · 1",
              summary: "Talk casually with friends; follow casual Shorts.", scene: "scene_shrine",
              souvenir: "souvenir_omamori", souvenirName: "Omamori charm", wordsTarget: 850,
              phrases: [
                p("matte", "ちょっと まって！", "wait a sec!", "ちょっと まって！", "ちょっと まって", "Wait a sec!", ["ちょっと", "まって"], ["まって", "待って"], "て-form request"),
                p("shiteru", "いま 〜してる", "I'm … right now", "いま たべてる", "いま たべてる", "I'm eating right now.", ["いま", "たべてる"], ["てる", "ている"], "〜ている"),
                p("tai", "〜したい！", "I want to …!", "ラーメンが たべたい！", "らーめんが たべたい", "I want to eat ramen!", ["ラーメン", "が", "たべたい"], ["たい"], "〜たい"),
                p("kara", "〜から", "because …", "さむいから かえる", "さむいから かえる", "It's cold, so I'm going home.", ["さむい", "から", "かえる"], ["から"], "〜から"),
              ],
              canDos: [CanDo(id: "casual", title: "Talked casually", stamp: "友達", phraseIds: ["matte", "shiteru"]),
                       CanDo(id: "want", title: "Said what I want", stamp: "願い", phraseIds: ["tai"]),
                       CanDo(id: "reason", title: "Gave a reason", stamp: "理由", phraseIds: ["kara"])],
              grammar: ["Plain form", "て-form: 〜ている · 〜てください", "〜から · 〜けど"], pin: (0.55, 0.32)),

        Place(id: "ramen", index: 5, name: "Ramen alley", japanese: "よこちょう", level: "N4 → N3",
              summary: "Tell what happened; give opinions and advice.", scene: "scene_reel",
              souvenir: "souvenir_ramen", souvenirName: "Ramen bowl", wordsTarget: 1150,
              phrases: [
                p("omou", "〜と おもう", "I think …", "おいしいと おもう", "おいしいと おもう", "I think it's tasty.", ["おいしい", "と", "おもう"], ["とおもう", "と思う"], "〜と思う"),
                p("taraii", "〜たら いいよ", "you should …", "やすんだら いいよ", "やすんだら いいよ", "You should rest.", ["やすんだら", "いいよ"], ["たらいい", "だらいい"], "〜たら"),
                p("houga", "A より B の ほうが", "B is more … than A", "ラーメンより すしの ほうが すき", "らーめんより すしの ほうが すき", "I like sushi more than ramen.", ["ラーメン", "より", "すし", "の", "ほうが", "すき"], ["ほうが", "方が"], "より / ほうが"),
                p("tekurete", "〜てくれて ありがとう", "thanks for …", "きてくれて ありがとう", "きてくれて ありがとう", "Thanks for coming.", ["きてくれて", "ありがとう"], ["てくれて"], "くれる"),
              ],
              canDos: [CanDo(id: "opinion", title: "Gave my opinion", stamp: "意見", phraseIds: ["omou"]),
                       CanDo(id: "advice", title: "Gave advice", stamp: "助言", phraseIds: ["taraii"]),
                       CanDo(id: "compare", title: "Compared things", stamp: "比較", phraseIds: ["houga"]),
                       CanDo(id: "thank", title: "Thanked someone", stamp: "感謝", phraseIds: ["tekurete"])],
              grammar: ["〜と思う · 〜かも", "たら / ば / と", "あげる・くれる・もらう"], pin: (0.22, 0.24)),

        Place(id: "castle", index: 6, name: "Castle town", japanese: "じょうかまち", level: "N3",
              summary: "Understand everyday Japanese Shorts; hold a conversation.", scene: "scene_castle",
              souvenir: "souvenir_castle", souvenirName: "Golden castle", wordsTarget: 1500,
              phrases: [
                p("mitai", "〜みたい！", "looks like …!", "ねこみたい！", "ねこみたい", "Looks like a cat!", ["ねこ", "みたい"], ["みたい"], "〜みたい"),
                p("kotoaru", "〜したこと ある？", "have you ever …?", "すしを たべたこと ある？", "すしを たべたこと ある", "Have you ever eaten sushi?", ["すし", "を", "たべたこと", "ある"], ["ことある", "ことがある"], "〜ことがある"),
                p("youni", "〜ように なった", "became able to …", "よめるように なった", "よめるように なった", "I became able to read it.", ["よめる", "ように", "なった"], ["ようになった", "ように"], "〜ようになる"),
                p("yoroshiku", "よろしく おねがいします", "nice to work with you", "よろしく おねがいします", "よろしく おねがいします", "Nice to work with you.", ["よろしく", "おねがい", "します"], ["よろしく"], "Polite keigo"),
              ],
              canDos: [CanDo(id: "guess", title: "Guessed from what I see", stamp: "推測", phraseIds: ["mitai"]),
                       CanDo(id: "experience", title: "Asked about experiences", stamp: "経験", phraseIds: ["kotoaru"]),
                       CanDo(id: "change", title: "Talked about change", stamp: "変化", phraseIds: ["youni"]),
                       CanDo(id: "polite", title: "Spoke politely", stamp: "礼儀", phraseIds: ["yoroshiku"])],
              grammar: ["〜そう · 〜らしい", "Passive & causative", "Polite keigo basics"], pin: (0.66, 0.15)),
    ]

    static let allPhrases: [Phrase] = places.flatMap(\.phrases)
    static let phraseById: [String: Phrase] = Dictionary(uniqueKeysWithValues: allPhrases.map { ($0.id, $0) })
    static func place(of phraseId: String) -> Place? { places.first { $0.phrases.contains { $0.id == phraseId } } }
    static let wordBadges = [50, 100, 250, 500, 1000, 1500]
}

// MARK: - When to say it (daily-life context for beginners)

extension Phrase {
    /// English-letter pronunciation of the example ("sumimasen").
    var romaji: String { Romanize.pronounced(exampleKana) }
    /// A short real-life scene for when to use the phrase.
    var usage: String? { Curriculum.usage[id] }
}

extension Curriculum {
    static let usage: [String: String] = [
        "hello": "Walking into a small shop or greeting someone during the day.",
        "thanks": "A clerk hands you your change, or a friend holds the door.",
        "sorry": "Getting a waiter's attention, squeezing past someone on a train, or a small apology.",
        "sugoi": "A friend shows you a great photo or a trick in a video.",
        "kawaii": "You see a puppy, a cute café drink or a little keychain.",
        "kudasai": "Ordering at a counter: point at the menu and add ください.",
        "hajimemashite": "The very first time you meet someone, before your name.",
        "watashiwa": "Introducing yourself: わたしは Sam です.",
        "suki": "Saying what you like: ねこが すきです (I like cats).",
        "nandesuka": "Pointing at an unfamiliar food or object in a shop.",
        "oishii": "Right after the first bite of something good.",
        "dokodesuka": "Lost near a station: stop someone and say すみません、えきは どこですか？",
        "doko": "Asking a friend where they're headed (not for directions).",
        "nanji": "Checking the time when you don't have your phone.",
        "masenka": "Inviting a friend: let's eat together?",
        "kippu": "At the station entrance, ask a staff member: すみません、きっぷは どこで かえますか？",
        "densha": "On the platform, check before boarding: この でんしゃは しぶやに いきますか？ They'll say はい or いいえ.",
        "ikura": "At a market stall, pointing at an item before buying.",
        "hitotsu": "Ordering a single item at a stand: one, please.",
        "meccha": "Casual: when food is really, really good (with friends).",
        "fukuro": "At the till the clerk asks ふくろは いりますか？ (need a bag?). Say いいえ、だいじょうぶです to decline.",
        "atatame": "Buying a bento or onigiri, the clerk asks あたためますか？ (heat it up?). Say はい、おねがいします for yes.",
        "matte": "Casual: asking a friend to wait a second.",
        "shiteru": "Texting a friend what you're doing right now.",
        "tai": "Saying what you want to do: I want to go to Kyoto!",
        "kara": "Giving a reason: because it's raining.",
        "omou": "Sharing your opinion softly: I think it's good.",
        "taraii": "Giving a friend a tip or suggestion.",
        "houga": "Comparing two things: the café is better than the station shop.",
        "tekurete": "Thanking someone for something specific they did for you.",
        "mitai": "Commenting on how something looks: looks like rain!",
        "kotoaru": "Asking about experiences: have you ever been to Osaka?",
        "youni": "Talking about progress: I became able to read kana.",
        "yoroshiku": "End of a self-introduction, or starting work with someone new.",
    ]
}
