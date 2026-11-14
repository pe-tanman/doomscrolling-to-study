import Foundation
import Combine
import UIKit
import os
@preconcurrency import WebKit

private let spikeLog = Logger(subsystem: "com.upscroll.app", category: "spike")

/// One learning word placed on one caption line of a video.
struct VideoTarget: Codable, Hashable {
    let entryId: String
    /// Caption line index, or `VideoTarget.title` for a word taken from the video title.
    let cueIndex: Int
    /// A refresher: a word you already know, shown in the subtitles only (no pause card), so every captioned
    /// Short still has Japanese in it when nothing new or due fits.
    var inlineOnly = false
    static let title = -1
    var isTitle: Bool { cueIndex == Self.title }
}

/// Per-video record. It's both the lesson input and a Phase 0 measurement row.
struct VideoRecord: Codable {
    /// A sponsored Short (detected by the bridge): no word cards.
    var isAd: Bool?
    var isDubbed: Bool?
    var info: VideoInfo?
    var sourceCues: [Cue] = []
    var japaneseCues: [Cue] = []
    var japaneseKind: String?
    var sourceStatus: Int?
    var sourceEmpty: Bool?
    var usedPot: Bool = false
    var firstSeen: Date = Date()
    /// Learning words for this video, in playback order, each on a different line.
    var targets: [VideoTarget] = []
    /// Targets whose pause-and-learn moment has already happened.
    var completed: Set<Int> = []
    /// "rules" (instant, on-device) until the Jev picks arrive, then "jev".
    var pickedBy = "rules"
    var jevRequested = false
    /// Nonverbal Short: object / listening / review moments instead of caption words.
    var nonverbalChecked = false
    var bonus: [BonusMoment] = []
    /// Phrase from this Short: the caption line picked to learn whole (Jev or offline rule).
    var phraseRequested: Bool?
    var phraseCue: Int?
    var phraseJa: String?
    var phraseEn: String?
    var phrasePickedBy: String?
    var phraseDone: Bool?
    /// Grammar chunk from this Short: the caption line, the grammar point and the piece to blank (see Grammar.swift).
    var grammarRequested: Bool?
    var grammarCue: Int?
    var grammarPoint: String?
    var grammarPiece: String?
    var grammarBefore: String?
    var grammarAfter: String?
    var grammarDistractors: [String]?
    var grammarJa: String?
    var grammarEn: String?
    var grammarPickedBy: String?
    var grammarDone: Bool?
    /// A question (word, grammar, phrase, picture, review or original card) has been shown on this Short.
    var cardShown: Bool?
    /// The "at least one question per Short" fallback was already added here.
    var fallbackAdded: Bool?
}

/// What the paused moment asks of the learner.
enum MomentKind: Equatable {
    /// First meetings: tap → hear → meaning, kana breakdown and the Japanese line.
    case learn
    /// Word met before: recall it first, then the same reveal. toJapanese: the English word is highlighted in the
    /// subtitle line and the options are Japanese (production); else the Japanese is swapped in → pick the meaning.
    case recall(options: [VocabEntry], toJapanese: Bool)
    /// Hiragana sound drill (brand-new learners): hear a kana with no text, pick it. kanaDrill is always true now.
    case listen(options: [VocabEntry], kanaDrill: Bool)
    /// Picture question built from a screenshot of the Short (Jev judges what's in the frame).
    /// frame is laid over the video at frameRect (screen points); box is in fractions of the frame.
    case picture(options: [VocabEntry], ask: PictureAsk, frame: UIImage?, frameRect: CGRect?, box: CGRect?)
    /// A word met in an earlier Short, asked again (spaced repetition inside the feed).
    /// toJapanese: "How do you say …?" with Japanese options; else the Japanese word → pick the meaning.
    case review(options: [VocabEntry], toJapanese: Bool, metIn: String)
    /// Review by ear: hear the word (nothing written), pick its meaning.
    case hearIt(options: [VocabEntry], metIn: String)
    /// Review by spelling: build the word from kana tiles for its meaning.
    case spell(tiles: [String], answer: [String], metIn: String)
    /// Review out loud: say the word for its meaning (on-device speech recognition).
    case say(metIn: String)

    var isQuiz: Bool { if case .learn = self { return false } else { return true } }
    /// Any "word from an earlier Short" card.
    var isReview: Bool {
        switch self {
        case .review, .hearIt, .spell, .say: return true
        default: return false
        }
    }
    /// The learner has to come up with the Japanese (so nothing on the card may show it first).
    var isProduction: Bool {
        switch self {
        case .recall(_, true), .review(_, true, _), .spell, .say: return true
        default: return false
        }
    }
    var options: [VocabEntry] {
        switch self {
        case .learn, .spell, .say: return []
        case .recall(let o, _), .listen(let o, _), .picture(let o, _, _, _, _), .review(let o, _, _), .hearIt(let o, _): return o
        }
    }
}

/// What a picture question asks about the screenshot.
enum PictureAsk: Equatable {
    /// The thing is outlined: what's it called in Japanese?
    case whatsThis
    /// What color is the outlined thing? (answer = a color word)
    case color(of: VocabEntry)
    /// No reliable outline: which of these is in the picture?
    case whichOne
}

/// Extra learning for Shorts with no speech (music, gameplay, pets, food…).
struct BonusMoment: Codable, Hashable {
    enum Kind: String, Codable { case picture, listen, review }
    let kind: Kind
    let entryId: String
    let optionIds: [String]
    /// Picture: "what" | "color" | "which"; the thing a color question is about; its box (left, top, right, bottom).
    var ask = ""
    var aboutId = ""
    var box: [Double] = []
    /// Review: the line and Short where the word was met, and the question direction.
    var line: String = ""
    var metIn: String = ""
    var toJapanese = false
    /// Review style: nil/"meaning" (or toJapanese), "listen", "spell", "say". Optional so older saves load.
    var style: String?
    var done = false
}

/// The paused "tap the word" moment.
struct LearningMoment: Identifiable, Equatable {
    let id = UUID()
    let videoId: String
    let targetIndex: Int
    let entry: VocabEntry
    let line: String
    let swapRange: Range<String.Index>?
    let japaneseLine: String?
    let numberInVideo: Int
    let totalInVideo: Int
    var kind: MomentKind = .learn
    /// The word came from the video title (shown early, before any caption line has it).
    var fromTitle = false
}

/// Phase 0 go/no-go numbers.
struct SpikeStats: Codable {
    var videosSeen = 0
    var withTrackList = 0
    var withSourceCues = 0
    var withJapaneseCues = 0
    var emptyResponses = 0
    var potRecovered = 0
    var withTargets = 0
    var targetsTotal = 0
    var pickedByJev = 0

    var sourceHitRate: Double { videosSeen == 0 ? 0 : Double(withSourceCues) / Double(videosSeen) }
    var japaneseHitRate: Double { videosSeen == 0 ? 0 : Double(withJapaneseCues) / Double(videosSeen) }
}

/// Talks to the page: pause/resume the active video.
@MainActor
final class WebController {
    weak var webView: WKWebView?
    func pause() { webView?.evaluateJavaScript("window.__dsPause && window.__dsPause()", completionHandler: nil) }
    func play() { webView?.evaluateJavaScript("window.__dsPlay && window.__dsPlay()", completionHandler: nil) }

    static let shortsURL = URL(string: "https://m.youtube.com/shorts")!
    /// The feed, optionally asking YouTube for Japanese content and a Japan region.
    static func feedURL(japanese: Bool) -> URL {
        japanese ? URL(string: "https://m.youtube.com/shorts?hl=ja&gl=JP&persist_hl=1&persist_gl=1")! : shortsURL
    }
    static let homeURL = URL(string: "https://m.youtube.com/")!
    /// Google sign-in that lands back on YouTube home. Happens inside the same web view so the
    /// login cookies end up in the feed's persistent data store.
    static let signInURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https%3A%2F%2Fm.youtube.com%2F")!

    func open(_ url: URL) { webView?.load(URLRequest(url: url)) }

    /// Signed in = YouTube's login cookies exist in the feed's data store.
    func checkSignedIn(_ done: @escaping @MainActor (Bool) -> Void) {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { cookies in
            let yes = cookies.contains { c in
                c.domain.hasSuffix("youtube.com") && (c.name == "LOGIN_INFO" || c.name == "SAPISID" || c.name == "__Secure-3PAPISID")
            }
            Task { @MainActor in done(yes) }
        }
    }

    /// Sign out by clearing Google/YouTube website data from the feed's store, then reload Shorts.
    func signOut(_ done: @escaping @MainActor () -> Void) {
        guard let store = webView?.configuration.websiteDataStore else { return }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let mine = records.filter { r in
                ["youtube.com", "google.com", "googlevideo.com", "ytimg.com"].contains { r.displayName.hasSuffix($0) }
            }
            store.removeData(ofTypes: types, for: mine) {
                Task { @MainActor in
                    self.open(Self.shortsURL)
                    done()
                }
            }
        }
    }
}

@MainActor
final class FeedSession: ObservableObject {
    @Published var records: [String: VideoRecord] = [:]
    @Published private(set) var order: [String] = []
    @Published private(set) var currentVideoId: String?
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var paused = true
    @Published private(set) var logs: [String] = []
    @Published var moment: LearningMoment? {
        didSet {
            if moment != nil { markCardShown() }
            if moment == nil, oldValue != nil { Speech.shared.stop() }   // card closed: no voice after it's gone
        }
    }
    /// An Upscroll original shown between real Shorts (curriculum v2: ~1 in 6 swipes).
    @Published var original: OriginalCard? {
        didSet {
            if original != nil { markCardShown() }
            if original == nil, oldValue != nil { Speech.shared.stop() }
            if (original == nil) != (oldValue == nil) { appendLog(original == nil ? "original closed" : "original shown \(original!.kind)") }
        }
    }
    /// A chunk / pattern question on the current Short (the rung between words and sentences).
    @Published var grammar: GrammarMoment? {
        didSet {
            if grammar != nil { markCardShown() }
            if grammar == nil, oldValue != nil { Speech.shared.stop() }
        }
    }
    /// Swipe number of the Short that last showed a grammar card.
    var lastGrammarSwipe: Int?
    /// Just unlocked a new practice type or finished kana practice: shown over the feed for a moment.
    @Published var unlock: UnlockEvent?
    /// A short "you're getting somewhere" message over the feed (words today, % to the next unlock, kana).
    @Published var nudge: ProgressNudge?
    var lastNudgeAt = Date.distantPast
    /// When the Short on screen became active (time on it, unlike currentTime, keeps counting when a short clip loops).
    var shortStartedAt = Date()
    /// Set when the daily scroll limit is reached: the root view shows the session recap.
    @Published var recapRequested = false
    /// Question Lab → RootView: "close" (dismiss sheets) or "recap".
    @Published var labRoute: String?
    /// The dashboard sheet is open: feed time is not counted.
    var dashboardOpen = false
    // Journey bookkeeping (see FeedSession+Journey.swift).
    var lastHeardTime: Double = 0
    var swipesThisSession = 0
    var swipesSinceOriginal = 0
    var swipesSinceLesson = 0
    /// The Upscroll lesson Short on screen (see LessonVideos.swift) and its checkpoints already shown.
    @Published var activeLesson: LessonVideo?
    @Published var lessonCheckpointsDone: Set<Int> = []
    /// Set while the feed jumps to a lesson Short, so that jump isn't counted as the learner's swipe.
    var openingLesson = false
    var originalTimes: [Date] = []
    /// Saved, so a relaunch on the same day doesn't show the limit recap again before any scrolling.
    var limitRecapShownDay: String {
        get { UserDefaults.standard.string(forKey: "limitRecapShownDay") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "limitRecapShownDay") }
    }
    /// Page currently shown in the web view (Shorts, YouTube home, Google sign-in…).
    @Published private(set) var pageURL: URL?
    var onShorts: Bool { pageURL?.path.hasPrefix("/shorts") ?? true }
    var onYouTube: Bool { pageURL?.host?.hasSuffix("youtube.com") ?? true }
    /// nil = not checked yet.
    @Published private(set) var signedIn: Bool?

    func refreshSignedIn() { web.checkSignedIn { [weak self] in self?.signedIn = $0 } }
    @Published var settings = LearnerSettings.load() {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.wordsPerVideo < oldValue.wordsPerVideo { trimTargets(to: settings.wordsPerVideo) }
        }
    }

    /// Fewer words per video: drop not-yet-shown extra words now, so the next card says "1 of 1", not "1 of 2".
    private func trimTargets(to limit: Int) {
        for (id, var r) in records where r.targets.count > limit {
            while r.targets.count > limit, !r.completed.contains(r.targets.count - 1) { r.targets.removeLast() }
            records[id] = r
        }
    }

    let vocab: VocabStore
    let wordBook: WordBook
    let journey: JourneyStore
    let web = WebController()
    private var clock: Timer?
    /// No word from the page bridge for 3 s: whatever is on screen is unknown, so show no subtitles.
    @Published private(set) var bridgeStale = false
    private var lastTickAt = Date.distantPast

    init(vocab: VocabStore = VocabStore(), wordBook: WordBook, journey: JourneyStore) {
        self.vocab = vocab
        self.wordBook = wordBook
        self.journey = journey
        if !ProcessInfo.processInfo.arguments.contains("-demoJourney") { journey.startSession(words: wordBook.words.count) }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkBridge(); self?.clockTick() }
        }
        #if DEBUG
        // `-seedReview <entryId> <correct>`: a word met 10 minutes ago in another Short (UI tests).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetWords") { wordBook.reset() }   // new-learner path (UI tests)
        if let i = args.firstIndex(of: "-seedReview"), i + 2 < args.count, let e = vocab.byId[args[i + 1]] {
            wordBook.seedForTesting(e, correct: Int(args[i + 2]) ?? 0,
                                    context: WordContext(videoId: "seed", title: "My morning routine",
                                                         line: "I'm so \(e.en.first ?? e.meaning) after work", japaneseLine: nil,
                                                         date: Date().addingTimeInterval(-600)))
        }
        // `-seedReviewSet`: a few due words at each review stage (new, getting there, strong), for UI tests.
        if args.contains("-seedReviewSet") {
            for (id, correct) in [("tired", 0), ("cat", 0), ("coffee", 1), ("dog", 2), ("water", 4), ("eat", 5)] {
                guard let e = vocab.byId[id] else { continue }
                wordBook.seedForTesting(e, correct: correct,
                                        context: WordContext(videoId: "seed", title: "My morning routine",
                                                             line: "I really want some \(e.en.first ?? e.meaning) right now, honestly.", japaneseLine: nil,
                                                             date: Date().addingTimeInterval(-600)))
            }
        }
        #endif
    }

    func pageChanged(_ url: URL?) {
        guard url != pageURL else { return }
        pageURL = url
        if !onShorts, moment != nil { moment = nil }
        // Swiped to another Short: drop the old video's subtitles right away, even before its player reports.
        if let id = Self.shortsId(url) {
            if id != currentVideoId { switchVideo(to: id, time: 0) }
        } else if currentVideoId != nil {
            currentVideoId = nil   // left Shorts / loading page: no caption is confirmed, so show none
            currentTime = 0
        }
        refreshSignedIn()
    }

    // MARK: Bridge events

    func handle(_ event: BridgeEvent) {
        switch event {
        case .video(let info):
            var r = records[info.videoId] ?? VideoRecord()
            r.info = info
            setRecord(r, for: info.videoId)
            appendLog("video \(info.videoId) tracks=\(info.tracks.map { "\($0.languageCode)\($0.kind == "asr" ? "(asr)" : "")" }.joined(separator: ","))")
        case .captions(let c):
            var r = records[c.videoId] ?? VideoRecord()
            switch c.role {
            case .source:
                if !c.cues.isEmpty { r.sourceCues = c.cues }
                r.sourceStatus = c.status
                r.sourceEmpty = c.empty
            case .japanese:
                if !c.cues.isEmpty { r.japaneseCues = c.cues; r.japaneseKind = c.kind }
            case .none:
                break
            }
            r.usedPot = r.usedPot || (c.usedPot ?? false)
            if !r.targets.contains(where: { !$0.isTitle }) && !r.sourceCues.isEmpty {
                // Captions can arrive after the Short started: don't place words on lines already gone.
                let playedTo = c.videoId == currentVideoId ? currentTime : 0
                var caps = chooseTargets(in: r.sourceCues, after: playedTo)
                if caps.isEmpty && playedTo > 0 {
                    // The play time can be stale right after a swipe; never end up with zero words.
                    caps = chooseTargets(in: r.sourceCues, after: 0)
                }
                r.targets = caps
                let words = r.targets.compactMap { vocab.byId[$0.entryId]?.kana }.joined(separator: ", ")
                appendLog("targets \(c.videoId) (from \(String(format: "%.1f", playedTo))s): \(words.isEmpty ? "none" : words)")
            }
            let askJev = settings.smartPicks && !r.jevRequested && !r.sourceCues.isEmpty
            if askJev { r.jevRequested = true }
            setRecord(r, for: c.videoId)
            if askJev { requestJevPicks(c.videoId) }
            planStructure(c.videoId)
            appendLog("captions \(c.videoId) \(c.role.rawValue) cues=\(c.cues.count) status=\(c.status.map(String.init) ?? "-")\(c.empty == true ? " EMPTY" : "")\(c.usedPot == true ? " pot" : "")\(c.note.map { " \($0)" } ?? "")")
        case .tick(let t):
            lastTickAt = Date()
            if bridgeStale { bridgeStale = false; appendLog("bridge ticking again") }
            // Empty id: the page shows a Short the bridge can't name yet. Show no subtitles until it can.
            if t.videoId.isEmpty {
                if currentVideoId != nil { appendLog("active video unknown (feed moved ahead of URL)") }
                currentVideoId = nil
                currentTime = 0
                paused = t.paused
                if moment != nil { moment = nil }
                return
            }
            if currentVideoId != t.videoId { switchVideo(to: t.videoId, time: t.currentTime) }
            if t.ad == true, var r = records[t.videoId], r.isAd != true { r.isAd = true; setRecord(r, for: t.videoId); appendLog("ad \(t.videoId): no words") }
            if t.dub == true, var r = records[t.videoId], r.isDubbed != true { r.isDubbed = true; setRecord(r, for: t.videoId); appendLog("auto-dubbed \(t.videoId)") }
            hearJapaneseLines(t.videoId, from: currentTime, to: t.currentTime)
            currentTime = t.currentTime
            if moment == nil, let sw = currentSwap { displayedSwaps.insert("\(t.videoId)|\(sw.entry.id)") }
            paused = t.paused
            // A card is open (mini-reel, quest, word, grammar, phrase): the Short stays paused. One pause isn't enough:
            // a mini-reel opens right at a swipe, and YouTube starts the new Short after our pause command.
            if !t.paused, moment != nil || original != nil || grammar != nil {
                web.pause()
                appendLog("paused \(t.videoId): a card is open")
            }
            // Nothing to teach from the captions 3 s in (no speech, or captions too slow): picture / review questions.
            // (Words from the video title are no longer asked: they rarely match what the Short is about.)
            if currentTime >= 3, var r = records[t.videoId], r.targets.isEmpty, !r.nonverbalChecked {
                r.nonverbalChecked = true
                setRecord(r, for: t.videoId)
                startNonverbal(t.videoId)
            }
            checkForMoment()
            ensureQuestion(t.videoId)
            recordPassiveEncounters()
        case .log(let s):
            appendLog(s)
        }
    }

    func setRecord(_ r: VideoRecord, for id: String) {
        if records[id] == nil { order.append(id) }
        records[id] = r
    }

    func appendLogPublic(_ s: String) { appendLog(s) }

    private func appendLog(_ s: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        logs.append("\(stamp) \(s)")
        spikeLog.info("\(s, privacy: .public)")
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }

    // MARK: Choosing learning words (Phase 0/1: rules; Phase 1+: Jev Choice + sense check)

    /// Forgetting curve gate: a word is shown only when it's new or due (recall dropped to ~90%).
    /// Words you still remember — including ones you answered easily — are skipped.
    func shouldShow(_ id: String) -> Bool {
        guard let p = wordBook.progress(id) else { return true }
        return p.isDue
    }

    #if DEBUG
    /// `-forceNonverbal`: treat every Short as having no talking (live captions vary run to run).
    static let forceNonverbal = ProcessInfo.processInfo.arguments.contains("-forceNonverbal")
    #endif

    /// Picks the learning words for one video. People swipe fast, so the FIRST word goes on the
    /// earliest usable line (ideally within the first few seconds); the rest are ranked by value.
    private func chooseTargets(in cues: [Cue], after playedTo: Double = 0) -> [VideoTarget] {
        #if DEBUG
        if Self.forceNonverbal { return [] }
        #endif
        struct Cand { let entry: VocabEntry; let cue: Int; let score: Double }
        var firstCue: [String: Int] = [:]
        var counts: [String: Int] = [:]
        for (i, cue) in cues.enumerated() where cue.end > playedTo + 0.4 {
            for m in vocab.candidates(in: cue.text, upTo: settings.jlptLevel) where shouldShow(m.entry.id) {
                counts[m.entry.id, default: 0] += 1
                if firstCue[m.entry.id] == nil { firstCue[m.entry.id] = i }
            }
        }
        let cands: [Cand] = firstCue.compactMap { id, cue in
            guard let e = vocab.byId[id] else { return nil }
            var s = 0.0
            if let p = wordBook.progress(id) {
                // Due: the more it has been forgotten, the more urgent.
                s += 2 + (1 - p.recallNow) * 4
            } else {
                s += 2                                        // new word
            }
            // Native Japanese words teach more vocabulary than respelled English; loanwords still fill in when nothing else fits.
            if e.loanword { s -= 1.5 }
            if e.level == settings.jlptLevel { s += 0.75 }      // the level being learned comes first
            s += min(Double(counts[id] ?? 1) - 1, 2) * 0.5    // repeated in the clip
            // Promo lines ("follow and subscribe", "link in bio") teach less than real conversation: rank them last.
            let line = cues[cue].text.lowercased()
            if ["follow", "subscribe", "like and share", "link in bio", "comment below", "share this", "check out my"].contains(where: line.contains) { s -= 2 }
            return Cand(entry: e, cue: cue, score: s)
        }.sorted { $0.score != $1.score ? $0.score > $1.score : $0.cue < $1.cue }

        var picked: [Cand] = []
        // 1) Earliest line with a not-yet-known word, best word on that line. Known words only
        //    if nothing else exists, so every Short teaches something quickly.
        let earliest: ([Cand]) -> Cand? = { $0.min(by: { a, b in a.cue != b.cue ? a.cue < b.cue : a.score > b.score }) }
        // First word: the earliest native-Japanese word when one comes within ~8 s of the earliest candidate.
        let anyFirst = earliest(cands)
        let nativeFirst = earliest(cands.filter { !$0.entry.loanword })
        let firstPick = nativeFirst.flatMap { n in anyFirst.map { cues[n.cue].start - cues[$0.cue].start <= 8 ? n : $0 } } ?? anyFirst
        if let early = firstPick {
            picked.append(early)
        }
        // 2) The rest by score: one word per line, lines ~2.5 s apart so pauses don't stack.
        for c in cands where picked.count < settings.wordsPerVideo {
            let clash = picked.contains { p in
                p.cue == c.cue || p.entry.id == c.entry.id || abs(cues[p.cue].start - cues[c.cue].start) < 2.5
            }
            if !clash { picked.append(c) }
        }
        // Not enough spread-out lines: allow closer ones rather than teach fewer than asked.
        for c in cands where picked.count < settings.wordsPerVideo
            && !picked.contains(where: { $0.cue == c.cue || $0.entry.id == c.entry.id }) {
            picked.append(c)
        }
        if picked.isEmpty {
            // Nothing new or due on these lines: still weave in one familiar word (inline only).
            for (i, cue) in cues.enumerated() where cue.end > playedTo + 0.4 {
                if let m = vocab.candidates(in: cue.text, upTo: settings.jlptLevel).first {
                    return [VideoTarget(entryId: m.entry.id, cueIndex: i, inlineOnly: true)]
                }
            }
        }
        return picked.sorted { $0.cue < $1.cue }.map { VideoTarget(entryId: $0.entry.id, cueIndex: $0.cue) }
    }

    // MARK: Jev word picks (TypeSafe, via the lesson server)

    /// The on-device rules place words instantly; Jev's picks replace the not-yet-shown ones
    /// when they arrive (usually well before the first line ends). Offline → rules stay.
    private func requestJevPicks(_ videoId: String) {
        #if DEBUG
        if Self.forceNonverbal { return }
        #endif
        guard let r = records[videoId] else { return }
        var candidates: [LessonRequest.CandidateDTO] = []
        for (i, cue) in r.sourceCues.enumerated() {
            // Every sense of a many-meaning word goes to Jev, which judges each against the line.
            for m in vocab.candidates(in: cue.text, upTo: settings.jlptLevel, allSenses: true) where shouldShow(m.entry.id) {
                let p = wordBook.progress(m.entry.id)
                let status = p == nil ? "new" : (p!.isKnown ? "known" : (p!.isDue ? "due" : "learning"))
                candidates.append(.init(cue: i, entryId: m.entry.id, word: String(cue.text[m.range]),
                                        kana: m.entry.kana, meaning: m.entry.meaning, status: status))
            }
        }
        guard !candidates.isEmpty else { return }
        let cues = r.sourceCues.enumerated().map { i, c in
            LessonRequest.CueDTO(i: i, start: c.start, end: c.end, text: c.text, ja: japaneseLine(for: c, in: r.japaneseCues))
        }
        let req = LessonRequest(videoId: videoId, title: r.info?.title ?? "", wordsPerVideo: settings.wordsPerVideo,
                                playedTo: videoId == currentVideoId ? currentTime : 0, cues: cues, candidates: candidates)
        let sent = Date()
        Task { [weak self] in
            do {
                let resp = try await LessonClient.pick(req)
                self?.applyJevPicks(resp, sent: sent)
            } catch {
                self?.appendLog("jev \(videoId) unavailable, keeping on-device picks: \(error.localizedDescription)")
            }
        }
    }

    private func applyJevPicks(_ resp: LessonResponse, sent: Date) {
        let id = resp.videoId
        guard var r = records[id] else { return }
        let ms = Int(Date().timeIntervalSince(sent) * 1000)
        for j in resp.judged ?? [] {
            appendLog(String(format: "jev %@ [%d] %@ sense=%.2f fits=%.2f useful=%.2f", j.entryId, j.cue, j.word, j.sense ?? -1, j.fits ?? -1, j.useful ?? -1))
        }
        // Jev's verdicts on the phone's own picks: a word Jev says is used with a different meaning
        // here is dropped even when Jev has no replacement (better no word than a wrong one).
        let judgedKeys = Set((resp.judged ?? []).map { "\($0.cue):\($0.entryId)" })
        // Also dropped: right meaning but not how Japanese says it (idioms, word-for-word swaps).
        let rejected = Set((resp.judged ?? []).filter { ($0.sense ?? 0) < 0.6 || ($0.fits ?? 1) < 0.55 }.map { "\($0.cue):\($0.entryId)" })
        let key: (VideoTarget) -> String = { "\($0.cueIndex):\($0.entryId)" }

        // Keep what the learner already saw (and an upcoming title word); replace the rest.
        let now = id == currentVideoId ? currentTime : 0
        let kept = r.targets.enumerated().filter { r.completed.contains($0.offset) }.map(\.element)
        var usedIds = Set(kept.map(\.entryId))
        let fresh = resp.targets
            .filter { $0.cue >= 0 && $0.cue < r.sourceCues.count && r.sourceCues[$0.cue].end > now + 0.3 && !usedIds.contains($0.entryId) }
            .map { VideoTarget(entryId: $0.entryId, cueIndex: $0.cue) }
        usedIds.formUnion(fresh.map(\.entryId))
        // Phone picks Jev never saw (beyond its shortlist) may fill remaining slots.
        let unjudged = r.targets.enumerated()
            .filter { !r.completed.contains($0.offset) && !$0.element.isTitle && !judgedKeys.contains(key($0.element)) && !usedIds.contains($0.element.entryId) }
            .map(\.element)
            .prefix(max(0, settings.wordsPerVideo - fresh.count))
        let droppedRules = r.targets.filter { rejected.contains(key($0)) }
        for t in droppedRules { appendLog("jev rejected \(vocab.byId[t.entryId]?.kana ?? t.entryId) on line \(t.cueIndex) (wrong sense, or not how Japanese says it)") }

        let completedTargets = Set(r.completed.compactMap { $0 < r.targets.count ? r.targets[$0] : nil })
        let start: (VideoTarget) -> Double = { $0.isTitle ? -1 : r.sourceCues[$0.cueIndex].start }
        let next = (kept + fresh + unjudged).filter { !$0.isTitle }.sorted { start($0) < start($1) }
        if next == r.targets {
            appendLog("jev \(id): agrees with on-device picks (\(ms)ms)")
            return
        }
        r.targets = next
        r.completed = Set(r.targets.indices.filter { completedTargets.contains(r.targets[$0]) })
        r.pickedBy = "jev"
        records[id] = r
        let words = r.targets.compactMap { vocab.byId[$0.entryId]?.kana }.joined(separator: ", ")
        appendLog("jev picks \(id): \(words) (\(ms)ms\(resp.cached == true ? ", cached" : "")\(resp.model.map { ", \($0)" } ?? ""))")
    }

    // MARK: Pause-and-learn moments

    /// When the line holding a learning word finishes, pause the video and show the word card.
    private func checkForMoment() {
        guard moment == nil, settings.pauseOnWord, let id = currentVideoId, var r = records[id] else { return }
        // Sponsored Shorts: words can still show in the subtitles, but no pause cards on marketing copy.
        if r.isAd == true { return }
        // An Upscroll lesson Short: only its own checkpoints, no automatic word or phrase cards.
        if let l = activeLesson, l.youtubeId == id { checkLessonCheckpoint(l); return }
        guard original == nil, grammar == nil else { return }
        if checkGrammarMoment(id, &r) { return }
        if checkPhraseMoment(id, &r) { return }
        if r.targets.isEmpty {
            if !r.bonus.isEmpty, cardAllowedHere, checkBonus(id, &r) { lastCardSwipe = swipesThisSession }
            return
        }
        // Questions stay about the Short on screen: no review cards for words from earlier Shorts
        // (those live in the dashboard's Review).
        if r.completed.count == r.targets.count {
            if !r.bonus.isEmpty, cardAllowedHere, checkBonus(id, &r) { lastCardSwipe = swipesThisSession }
            return
        }
        for (i, target) in r.targets.enumerated() where !r.completed.contains(i) {
            guard let entry = vocab.byId[target.entryId] else { continue }
            let line: String
            let ja: String?
            var cueRange: Range<String.Index>?
            if target.isTitle { continue } else {   // title words (older saves) are no longer asked
                guard target.cueIndex >= 0, target.cueIndex < r.sourceCues.count else { continue }
                let cue = r.sourceCues[target.cueIndex]
                let next = target.cueIndex + 1 < r.sourceCues.count ? r.sourceCues[target.cueIndex + 1].start : cue.end
                let lineEnd = max(cue.start + 0.6, min(cue.end, next))
                guard currentTime >= lineEnd - 0.2 && currentTime < lineEnd + 2.5 else { continue }
                // Auto-captions split sentences mid-way: borrow the neighbouring lines so the card reads as a sentence.
                let snip = Self.sentenceSnippet(r.sourceCues, at: target.cueIndex)
                line = snip.text
                cueRange = snip.cueRange
                // Japanese for exactly the same caption lines as the English snippet (not just the middle one).
                let span = Cue(start: snip.start, end: snip.end, text: "")
                let jaParts = r.japaneseCues.filter { overlap($0, span) > 0.5 * ($0.end - $0.start) }.map(\.text)
                ja = jaParts.isEmpty ? japaneseLine(for: cue, in: r.japaneseCues) : jaParts.joined(separator: " ")
            }

            r.completed.insert(i)
            records[id] = r
            if !cardAllowedHere || target.inlineOnly || structureSuppresses(target, index: i, in: r) {
                // Pace setting: no pause on this Short. A subtitle word still counts as met (it was on screen);
                // a title word was never shown by us, so it doesn't count and won't be reviewed.
                if target.isTitle { continue }
                guard displayedSwaps.contains("\(id)|\(entry.id)") else { continue }   // never drawn: don't count
                wordBook.recordEncounter(entry, context: WordContext(videoId: id, title: r.info?.title ?? "",
                                                                     line: line, japaneseLine: ja, date: Date()))
                continue
            }
            lastCardSwipe = swipesThisSession
            let matches = vocab.candidates(in: line, allSenses: true).filter { $0.entry.id == entry.id }
            let swap = matches.first { m in cueRange.map { $0.contains(m.range.lowerBound) } ?? true } ?? matches.first
            // Met it before? Make them recall it first instead of just showing it again.
            var kind = MomentKind.learn
            if let p = wordBook.progress(entry.id), p.timesSeen >= 1 {   // due again: recall before showing
                kind = .recall(options: (vocab.plausibleDistractors(for: entry, count: 2) + [entry]).shuffled(),
                               toJapanese: askJapanese(p, in: id))
            }
            if let ja { noticePhrases(in: ja, skill: .reading) }
            moment = LearningMoment(videoId: id, targetIndex: i, entry: entry, line: line,
                                    swapRange: swap?.range, japaneseLine: ja,
                                    numberInVideo: i + 1, totalInVideo: r.targets.count, kind: kind,
                                    fromTitle: target.isTitle)
            web.pause()
            wordBook.recordEncounter(entry, context: WordContext(videoId: id, title: r.info?.title ?? "",
                                                                 line: line, japaneseLine: ja, date: Date()))
            // Asked for the Japanese: saying it first would give the answer away (it plays after answering).
            if settings.autoSpeak && !kind.isProduction { Speech.shared.say(entry.kana) } else { Speech.shared.prefetch(entry.mainKana) }
            appendLog("moment \(entry.kana) at \(String(format: "%.1f", currentTime))s")
            return
        }
    }

    /// The cue plus the previous/next cue when the sentence clearly continues across them (max ~24 words).
    static func sentenceSnippet(_ cues: [Cue], at i: Int) -> (text: String, cueRange: Range<String.Index>, start: Double, end: Double) {
        func clean(_ t: String) -> String {
            var x = t.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            while x.hasPrefix(">") { x = String(x.dropFirst()).trimmingCharacters(in: .whitespaces) }
            return x
        }
        let ends: Set<Character> = [".", "!", "?", "…"]
        let mid = clean(cues[i].text)
        var before = "", after = ""
        if i > 0 {
            let prev = clean(cues[i - 1].text)
            let startsSentence = mid.first.map { $0.isUppercase } ?? false
            if !startsSentence, let last = prev.last, !ends.contains(last), !prev.hasPrefix("["),
               prev.split(separator: " ").count + mid.split(separator: " ").count <= 18 { before = prev + " " }
        }
        if i + 1 < cues.count, let last = mid.last, !ends.contains(last) {
            let next = clean(cues[i + 1].text)
            if !next.hasPrefix("["), (before + mid + " " + next).split(separator: " ").count <= 24 { after = " " + next }
        }
        let text = before + mid + after
        let lo = text.index(text.startIndex, offsetBy: before.count)
        let hi = text.index(lo, offsetBy: mid.count)
        let start = before.isEmpty ? cues[i].start : cues[i - 1].start
        let end = after.isEmpty ? cues[i].end : cues[i + 1].end
        return (text, lo..<hi, start, end)
    }

    /// Without pause mode, words still count as met when their line plays.
    private func recordPassiveEncounters() {
        guard !settings.pauseOnWord, let id = currentVideoId, var r = records[id], r.isAd != true else { return }
        for (i, target) in r.targets.enumerated() where !r.completed.contains(i) {
            guard target.cueIndex >= 0, target.cueIndex < r.sourceCues.count, let e = vocab.byId[target.entryId] else { continue }
            let cue = r.sourceCues[target.cueIndex]
            if currentTime >= cue.end, displayedSwaps.contains("\(id)|\(e.id)") {
                r.completed.insert(i)
                wordBook.recordEncounter(e, context: WordContext(videoId: id, title: r.info?.title ?? "", line: cue.text,
                                                                 japaneseLine: japaneseLine(for: cue, in: r.japaneseCues), date: Date()))
            }
        }
        records[id] = r
    }

    func hearMoment() {
        guard let m = moment else { return }
        Speech.shared.say(m.entry.kana)
        wordBook.recordHeard(m.entry.id)
    }

    func hearJapaneseLine() {
        guard let ja = moment?.japaneseLine else { return }
        Speech.shared.say(ja)
    }

    /// Recall moment answered inside the feed: feeds the same spaced-repetition schedule as Review.
    /// `seconds`: time to answer. Right and fast = easy recall → the word is pushed much further out.
    func answerRecall(correct: Bool, seconds: Double = .infinity) {
        guard let m = moment else { return }
        if m.entry.pos != "kana" {
            wordBook.recordAnswer(m.entry.id, correct: correct, easy: correct && seconds <= Memory.easySeconds)
        } else if correct {
            KanaProgress.shared.recordRight(m.entry.kana)
        }
        Speech.shared.say(m.entry.kana)
    }

    func finishMoment(known: Bool = false) {
        guard let m = moment else { return }
        if known { wordBook.claimKnown(m.entry.id) }
        moment = nil
        lastMomentEnded = Date()
        web.play()
        checkUnlocks()
    }

    /// After an answer: a new practice type or finished kana practice gets its moment over the feed.
    func checkUnlocks() {
        if let e = Unlocks.check(wordsLearned: wordBook.learnedCount) {
            unlock = e
            appendLog("unlock: \(e.title)")
            return
        }
        // Otherwise, now and then, a milestone message (at most one per 90 s so it stays special).
        guard Date().timeIntervalSince(lastNudgeAt) > 90,
              let n = Nudges.next(newWordsToday: wordBook.newToday, dailyGoal: settings.dailyGoal,
                                  wordsLearned: wordBook.learnedCount) else { return }
        lastNudgeAt = Date()
        nudge = n
        appendLog("nudge: \(n.text)")
    }

    var lastMomentEnded = Date.distantPast
    /// Swipe number of the Short that last showed a phrase-from-this-Short card.
    var lastPhraseSwipe: Int?
    /// Swipe number of the Short that last showed a word card (for the card pace setting).
    var lastCardSwipe: Int?
    /// "videoId|entryId" for yellow words that were actually drawn in the subtitles. Only these count as met
    /// without a card (the badge must never count a word the learner couldn't see).
    var displayedSwaps: Set<String> = []

    /// Pace: false when this Short should play through without a card.
    var cardAllowedHere: Bool {
        if settings.cardEvery == 0 { return false }   // cards only when the learner asks (あ → Review)
        guard settings.cardEvery > 1, let last = lastCardSwipe, last != swipesThisSession else { return true }
        return swipesThisSession < last || swipesThisSession - last >= settings.cardEvery   // new session resets the count
    }

    // MARK: Nonverbal Shorts: picture question (Jev on a screenshot) + listening + review

    /// Things a beginner can point at in a video frame (word-list ids).
    static let pictureWords = ["coffee", "camera", "tv", "pizza", "bus", "taxi", "cake", "bread", "phone", "computer", "shirt",
        "beer", "juice", "chocolate", "milk", "ramen", "burger", "chicken", "banana", "door", "table", "bed", "ball", "present",
        "cat", "dog", "bird", "water", "rice", "fish", "meat", "egg", "tea", "apple", "sushi", "car", "train", "bike", "plane",
        "house", "money", "baby", "child", "man", "woman", "girl", "boy", "person", "book", "shoes", "hat", "bag",
        "sun", "sky", "sea", "mountain", "river", "tree", "flower", "window"]
    static let colorWords = ["red", "blue", "white", "black", "green", "yellow"]
    /// Below this the outline might point at the wrong thing, so we ask "Which one can you see?" instead.
    static let boxMin = 0.4
    /// Lowest box confidence still good enough to outline the thing on a "Which one can you see?" card.
    /// Picture questions without any outline-able box aren't asked at all.
    static let outlineMin = 0.25

    /// Screenshots of recent nonverbal Shorts, shown on their picture cards.
    var frames: [String: (image: UIImage, rect: CGRect)] = [:]

    /// In almost every frame (people, background): never the answer of a picture question,
    /// or beginners get ひと / おとこ over and over. Still fine as caption words.
    static let commonPictureWords: Set<String> = ["person", "man", "woman", "boy", "girl", "child", "baby", "sky", "tree", "shirt"]
    /// The last answers of picture questions (kept across launches), so the same few words don't repeat.
    private var recentPictureWords: [String] {
        get { UserDefaults.standard.stringArray(forKey: "picture.recent") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.suffix(12)), forKey: "picture.recent") }
    }

    /// Weighted random choice: people/background words never; recent answers excluded (unless nothing else);
    /// known words ¼ as likely, words still being learned a little more likely.
    private func pickPictureWord(_ ids: [String]) -> String? {
        let recent = Set(recentPictureWords)
        // Same level rule as captions: your JLPT level and easier (picture words used to ignore it).
        let usable = ids.filter { id in
            guard let e = vocab.byId[id] else { return false }
            return e.level >= settings.jlptLevel && !Self.commonPictureWords.contains(id) && shouldShow(id)
        }
        let fresh = usable.filter { !recent.contains($0) }
        let pool = fresh.isEmpty ? usable : fresh
        let weighted = pool.map { id -> (String, Double) in
            // Due words a bit more likely than brand-new ones (they're about to be forgotten).
            return (id, wordBook.progress(id) == nil ? 1.0 : 1.5)
        }
        var r = Double.random(in: 0..<max(weighted.reduce(0) { $0 + $1.1 }, .leastNonzeroMagnitude))
        for (id, w) in weighted { r -= w; if r < 0 { return id } }
        return weighted.last?.0
    }

    func startNonverbal(_ videoId: String) {
        let title = records[videoId]?.info?.title ?? ""
        Task { [weak self] in
            guard let self else { return }
            // 1) Picture questions: screenshot of the video → Jev says what's in it → code builds the questions.
            var pictures: [BonusMoment] = []
            if self.settings.smartPicks, Plan.allows(.pictureQuestions), let frame = await FrameGrabber.grab(self.web.webView) {
                if self.frames.count > 6 { self.frames.removeAll() }
                self.frames[videoId] = (frame.image, frame.screenRect)
                do {
                    let resp = try await LessonClient.picture(self.pictureRequest(videoId: videoId, title: title, jpeg: frame.jpeg))
                    pictures = self.pictureQuestions(resp)
                    self.appendLog("jev picture \(videoId): sees \(resp.visible.prefix(4).joined(separator: ", ")) (\(resp.ms ?? -1)ms) → \(pictures.map(\.ask).joined(separator: "+"))")
                } catch {
                    self.appendLog("jev picture unavailable: \(error.localizedDescription)")
                }
            }

            // 2) Brand-new learners only: a hiragana sound drill. (No review of words from earlier Shorts here:
            //    questions are about the Short on screen.) At most 1–3 cards per Short.
            for b in pictures + [self.listenBonus()].compactMap({ $0 }) { self.addBonus(b, to: videoId) }
        }
    }

    private func pictureRequest(videoId: String, title: String, jpeg: Data) -> PictureRequest {
        func cand(_ id: String) -> PictureRequest.Candidate? {
            guard let e = vocab.byId[id] else { return nil }
            let p = wordBook.progress(id)
            let status = p == nil ? "new" : (p!.isKnown ? "known" : (p!.isDue ? "due" : "learning"))
            return .init(entryId: id, en: e.en.first ?? e.meaning, status: status)
        }
        return PictureRequest(videoId: videoId, title: title,
                              image: .init(format: "jpg", data_base64: jpeg.base64EncodedString()),
                              candidates: Self.pictureWords.compactMap(cand), colors: Self.colorWords.compactMap(cand),
                              avoid: recentPictureWords)
    }

    /// Code builds the questions from Jev's judgments: an outlined "What's this?" when the box is reliable,
    /// else "Which one can you see?"; plus "What color is it?" when the color is clear.
    private func pictureQuestions(_ r: PictureResponse) -> [BonusMoment] {
        let absent = r.absent.filter { vocab.byId[$0] != nil }.shuffled()
        guard absent.count >= 2 else { return [] }
        // Outlines must point at one clear thing: big boxes (a whole head, a person) make "what's outlined?" a guess,
        // so those things fall back to "Which one can you see?".
        let boxed = r.things.filter { t in
            guard let b = t.box, b.confidence >= Self.boxMin else { return false }
            let w = b.right - b.left, h = b.bottom - b.top
            // Not too big (a whole head) and not too small/thin to recognise (a far-off sliver).
            return w * h <= 0.18 && w * h >= 0.012 && min(w, h) >= 0.06
        }
        func edges(_ b: PictureResponse.Box?) -> [Double] { b.map { [$0.left, $0.top, $0.right, $0.bottom] } ?? [] }

        // Random, not "most obvious": otherwise every Short with people would ask ひと.
        var out: [BonusMoment] = []
        var asked: String?
        if let id = pickPictureWord(boxed.map(\.entryId)), let t = boxed.first(where: { $0.entryId == id }) {
            // One distractor that is also in the picture (the sheep next to the outlined dog), so the answer
            // needs the word, not just "which of these could be here". The outline says which one is meant.
            // Never a second right answer among the options (another word for the same thing).
            let differs = { (o: String) in guard let a = self.vocab.byId[o], let b = self.vocab.byId[id] else { return false }; return !self.vocab.equivalent(a, b) }
            let alsoVisible = r.visible.filter { $0 != id && differs($0) }.shuffled().prefix(1)
            let opts = [id] + alsoVisible + absent.filter(differs).prefix(2 - alsoVisible.count)
            out.append(BonusMoment(kind: .picture, entryId: id, optionIds: opts.shuffled(),
                                   ask: "what", box: edges(t.box)))
            asked = id
        } else if let v = pickPictureWord(r.things.filter { ($0.box?.confidence ?? 0) >= Self.outlineMin }.map(\.entryId)) {
            // No tight box for "What's this?": still only ask about something we can outline (a looser box is fine
            // for "Which one can you see?", it just has to point at the right thing).
            let ring = r.things.first { $0.entryId == v && ($0.box?.confidence ?? 0) >= Self.outlineMin }?.box
            let differs = { (o: String) in guard let a = self.vocab.byId[o], let b = self.vocab.byId[v] else { return false }; return !self.vocab.equivalent(a, b) }
            out.append(BonusMoment(kind: .picture, entryId: v, optionIds: ([v] + absent.filter(differs).prefix(2)).shuffled(), ask: "which", box: edges(ring)))
            asked = v
        }
        if let asked { recentPictureWords = recentPictureWords.filter { $0 != asked } + [asked] }
        // Color: about a different outlined thing when there is one, so one Short teaches two nouns.
        // Only clearly identifiable colors: confident judgments, and an even higher bar for colors that lighting
        // easily shifts (a tan table read as "yellow"), so a beginner never has to guess about lighting.
        let shifty: Set<String> = ["yellow", "brown", "orange", "beige", "gray", "grey", "purple", "pink",
                                    "jp:黄色い|きいろい", "jp:茶色|ちゃいろ", "jp:茶色い|ちゃいろい"]
        let colored = boxed.filter { t in
            guard let c = t.color, !Self.commonPictureWords.contains(t.entryId) else { return false }
            return c.confidence >= (shifty.contains(c.entryId) ? 0.92 : 0.8)
        }
        if let t = colored.first(where: { $0.entryId != asked }) ?? colored.first,
           let c = t.color?.entryId, vocab.byId[c] != nil, shouldShow(c) {
            let others = Self.colorWords.filter { $0 != c && vocab.byId[$0] != nil }.shuffled().prefix(2)
            out.append(BonusMoment(kind: .picture, entryId: c, optionIds: ([c] + others).shuffled(),
                                   ask: "color", aboutId: t.entryId, box: edges(t.box)))
        }
        return out
    }

    /// Hiragana sound drill for brand-new learners (no words collected yet): hear a kana, pick it.
    /// `always`: also for other learners, as the last-resort question on a Short with nothing else to ask.
    /// Until kana practice is complete (every basic sound picked right once), Shorts without speech keep a sound drill.
    private func listenBonus(always: Bool = false) -> BonusMoment? {
        guard always || wordBook.words.isEmpty || !KanaProgress.shared.isComplete else { return nil }
        let k = KanaProgress.shared.nextDrill()
        return BonusMoment(kind: .listen, entryId: "kana:" + k,
                           optionIds: Kana.drillOptions(for: k).map { "kana:" + $0 })
    }

    /// Subtitle word met before: on a Short spoken in Japanese (English subtitles) you hear the Japanese, so it's
    /// Japanese → meaning. Otherwise mostly English → Japanese (coming up with the word teaches more than
    /// recognizing it): recognized once already, 4 in 5 ask for the Japanese; still shaky, half and half.
    func askJapanese(_ p: WordProgress, in videoId: String) -> Bool {
        if isJapaneseAudio(videoId) { return false }
        return Double.random(in: 0..<1) < (p.correct >= 1 ? 0.8 : 0.5)
    }

    /// Word-list entry, or a synthetic kana entry for the listening drill.
    private func cardEntry(_ id: String) -> VocabEntry? {
        if id.hasPrefix("kana:") { return Kana.drillEntry(String(id.dropFirst(5))) }
        return vocab.byId[id]
    }

    private func addBonus(_ b: BonusMoment, to videoId: String) {
        guard var r = records[videoId], r.targets.isEmpty,   // speech words arrived meanwhile
              // Words per video also caps the total cards on a Short (pictures, reviews, kana) at 1–3.
              r.bonus.count < max(1, settings.wordsPerVideo) else { return }
        r.bonus.append(b)
        records[videoId] = r
        appendLog("bonus \(b.kind.rawValue) \(videoId): \(vocab.byId[b.entryId]?.kana ?? b.entryId)")
    }

    /// Shows the next pending nonverbal moment (spaced ≥ 4 s after the previous card).
    // MARK: At least one question per Short

    private func markCardShown() {
        guard let id = currentVideoId, var r = records[id], r.cardShown != true else { return }
        r.cardShown = true
        records[id] = r
    }

    /// When the next planned question on this Short will come (caption word, grammar, phrase or pending bonus).
    private func nextPlannedCard(_ r: VideoRecord) -> Double? {
        func lineEnd(_ i: Int) -> Double? { i >= 0 && i < r.sourceCues.count ? r.sourceCues[i].end : nil }
        var times: [Double] = []
        for (i, t) in r.targets.enumerated() where !r.completed.contains(i) && !t.inlineOnly && !t.isTitle {
            if let e = lineEnd(t.cueIndex), e >= currentTime - 0.5 { times.append(e) }
        }
        if let g = r.grammarCue, r.grammarDone != true, let e = lineEnd(g) { times.append(e) }
        if let p = r.phraseCue, r.phraseDone != true, let e = lineEnd(p) { times.append(e) }
        return times.min()
    }

    /// A word on a caption line of this Short that has already played (most recent line first).
    private func showHeardWord(_ id: String, _ r: VideoRecord) -> Bool {
        let used = Set(r.targets.map(\.entryId))
        for i in r.sourceCues.indices.reversed() where r.sourceCues[i].end <= currentTime + 0.3 {
            // Safe senses only: many-meaning words and set phrases are never asked without Jev's check.
            let cands = vocab.candidates(in: r.sourceCues[i].text, upTo: settings.jlptLevel).filter { $0.entry.kana.count >= 2 }
            guard let m = cands.first(where: { !used.contains($0.entry.id) && wordBook.progress($0.entry.id)?.isKnown != true })
                    ?? cands.first else { continue }
            let snip = Self.sentenceSnippet(r.sourceCues, at: i)
            let span = Cue(start: snip.start, end: snip.end, text: "")
            let jaParts = r.japaneseCues.filter { overlap($0, span) > 0.5 * ($0.end - $0.start) }.map(\.text)
            let ja = jaParts.isEmpty ? japaneseLine(for: r.sourceCues[i], in: r.japaneseCues) : jaParts.joined(separator: " ")
            let swap = vocab.candidates(in: snip.text, allSenses: true).first { $0.entry.id == m.entry.id && snip.cueRange.contains($0.range.lowerBound) }
            var kind = MomentKind.learn
            if let p = wordBook.progress(m.entry.id), p.timesSeen >= 1 {
                kind = .recall(options: (vocab.plausibleDistractors(for: m.entry, count: 2) + [m.entry]).shuffled(),
                               toJapanese: askJapanese(p, in: id))
            }
            moment = LearningMoment(videoId: id, targetIndex: -1, entry: m.entry, line: snip.text, swapRange: swap?.range,
                                    japaneseLine: ja, numberInVideo: 1, totalInVideo: 1, kind: kind)
            web.pause()
            wordBook.recordEncounter(m.entry, context: WordContext(videoId: id, title: r.info?.title ?? "", line: snip.text,
                                                                   japaneseLine: ja, date: Date()))
            if settings.autoSpeak && !kind.isProduction { Speech.shared.say(m.entry.kana) } else { Speech.shared.prefetch(m.entry.mainKana) }
            appendLog("question fallback \(id): heard word \(m.entry.kana) on line \(i)")
            return true
        }
        return false
    }

    /// Every Short asks at least one question, always about this Short. 4 s in, if nothing was asked and nothing
    /// is coming in the next 2.5 s: show a pending picture card now, else a word from a line that already played
    /// (recall if met before), else a kana sound.
    func ensureQuestion(_ id: String) {
        // 4 s on this Short (wall clock: a 3-second clip loops, so its play time never reaches 4).
        guard settings.cardEvery != 0, settings.pauseOnWord, onShorts, id == currentVideoId,
              Date().timeIntervalSince(shortStartedAt) >= 4, !paused,
              moment == nil, grammar == nil, original == nil, activeLesson?.youtubeId != id,
              var r = records[id], r.cardShown != true, r.isAd != true else { return }
        if let next = nextPlannedCard(r), next <= currentTime + 2.5 { return }
        if !r.bonus.contains(where: { !$0.done }) {
            guard r.fallbackAdded != true else { return }
            r.fallbackAdded = true
            records[id] = r
            // A word from a line of this Short that already played; else a kana sound.
            if showHeardWord(id, r) { lastCardSwipe = swipesThisSession; return }
            guard let b = listenBonus(always: true) else { return }
            r.bonus.append(b)
            appendLog("question fallback \(id): kana \(b.entryId)")
        }
        records[id] = r   // saved first: showing the card marks this Short as asked
        if checkBonus(id, &r, force: true) { lastCardSwipe = swipesThisSession }
    }

    private func checkBonus(_ id: String, _ r: inout VideoRecord, force: Bool = false) -> Bool {
        // Never the moment a Short loads (let it start, keep the swipe free), and space cards on one Short ≥ 10 s.
        guard force || (currentTime >= 3 && Date().timeIntervalSince(lastMomentEnded) > 10),
              let i = r.bonus.firstIndex(where: { !$0.done }),
              let entry = cardEntry(r.bonus[i].entryId) else { return false }
        let b = r.bonus[i]
        r.bonus[i].done = true
        records[id] = r
        let options = b.optionIds.compactMap { cardEntry($0) }
        let title = r.info?.title ?? ""
        let kind: MomentKind
        let line: String
        var swap: Range<String.Index>?
        switch b.kind {
        case .picture:
            let ask: PictureAsk = b.ask == "color" ? .color(of: vocab.byId[b.aboutId] ?? entry)
                                : b.ask == "which" ? .whichOne : .whatsThis
            let box = b.box.count == 4 ? CGRect(x: b.box[0], y: b.box[1], width: b.box[2] - b.box[0], height: b.box[3] - b.box[1]) : nil
            kind = .picture(options: options, ask: ask, frame: frames[id]?.image, frameRect: frames[id]?.rect, box: box)
            line = ""
        case .listen:
            kind = .listen(options: options, kanaDrill: b.entryId.hasPrefix("kana:"))
            line = ""   // nothing written: it's an ear-only question
        case .review:
            switch b.style {
            case "listen": kind = .hearIt(options: options, metIn: b.metIn)
            case "spell":
                if let t = Kana.spellTiles(for: entry.mainKana, extra: 2) { kind = .spell(tiles: t.tiles, answer: t.answer, metIn: b.metIn) }
                else { kind = .review(options: options, toJapanese: true, metIn: b.metIn) }
            case "say": kind = .say(metIn: b.metIn)
            default: kind = .review(options: options, toJapanese: b.toJapanese, metIn: b.metIn)
            }
            let english = kind.isProduction
            var l = b.line.isEmpty ? (english ? entry.meaning : entry.kana) : b.line
            // Older saved picture notes said "this Short", which reads as the clip behind the card.
            l = l.replacingOccurrences(of: "Seen in this Short:", with: "Spotted in that Short's picture:")
                 .replacingOccurrences(of: " in this Short is ", with: " in that Short was ")
            // Japanese → meaning: show the old line with the Japanese word swapped in.
            // English → Japanese: show the plain English line (the question names the word anyway).
            if case .hearIt = kind {
                l = ""   // ear-only: nothing written that gives it away
            } else if !english {
                swap = vocab.candidates(in: l, allSenses: true).first { $0.entry.id == entry.id }?.range
                // No natural swap (e.g. a picture note): never print the answer. Put the Japanese word in its place.
                if swap == nil {
                    for form in ([entry.meaning] + entry.en).sorted(by: { $0.count > $1.count }) where !form.isEmpty {
                        if let r = l.range(of: form, options: [.caseInsensitive]) {
                            l.replaceSubrange(r, with: entry.kana)
                            break
                        }
                    }
                    if let r = l.range(of: entry.kana) { swap = r } else { l = entry.kana; swap = l.startIndex..<l.endIndex }
                }
            }
            line = l
        }
        moment = LearningMoment(videoId: id, targetIndex: -1 - i, entry: entry, line: line, swapRange: swap, japaneseLine: nil,
                                numberInVideo: i + 1, totalInVideo: r.bonus.count, kind: kind)
        web.pause()
        if b.kind == .listen { Speech.shared.say(entry.kana); wordBook.recordHeard(entry.id) }
        if case .hearIt = kind { Speech.shared.say(entry.mainKana) }
        // Seeing the thing in a Short counts as meeting its word there.
        if b.kind == .picture {
            let what = b.ask == "color" ? "The \(vocab.byId[b.aboutId]?.meaning ?? "thing") in that Short was \(entry.meaning)"
                                        : "Spotted in that Short's picture: \(entry.meaning)"
            wordBook.recordEncounter(entry, context: WordContext(videoId: id, title: title, line: what, japaneseLine: nil, date: Date()))
        }
        appendLog("moment \(b.kind.rawValue) \(entry.kana) at \(String(format: "%.1f", currentTime))s")
        return true
    }

    /// One place for "a different Short is now on screen".
    private func switchVideo(to id: String, time: Double) {
        guard currentVideoId != id else { return }
        appendLog("active video \(id)")
        currentVideoId = id
        currentTime = time
        shortStartedAt = Date()
        if records[id] == nil { setRecord(VideoRecord(), for: id) }
        if moment != nil && moment?.videoId != id { moment = nil }   // user swiped away
        if grammar != nil && grammar?.videoId != id { grammar = nil }
        journey.shortStarted(japaneseAudio: isJapaneseAudio(id))
        lastHeardTime = 0
        // The jump into a lesson Short isn't a swipe of the learner's (that swipe was already counted).
        if openingLesson { openingLesson = false } else {
            swipesThisSession += 1
            swipesSinceOriginal += 1
            swipesSinceLesson += 1
        }
        // Lesson Shorts: entering one starts its checkpoints; leaving one counts it as watched once it was played through.
        if let l = activeLesson, l.youtubeId != id {
            if lessonCheckpointsDone.count >= l.checkpoints.count { LessonLibrary.shared.markWatched(l) }
            activeLesson = nil
        }
        if let l = LessonLibrary.shared.lesson(youtubeId: id) {
            activeLesson = l
            lessonCheckpointsDone = []
            appendLog("lesson \(l.id) started")
            return
        }
        if maybeShowLesson() { return }
        maybeShowOriginal()
    }

    static func shortsId(_ url: URL?) -> String? {
        guard let url, url.host?.hasSuffix("youtube.com") == true else { return nil }
        let parts = url.path.split(separator: "/")
        guard let i = parts.firstIndex(of: "shorts"), i + 1 < parts.count else { return nil }
        let id = String(parts[i + 1])
        return id.count >= 6 ? id : nil
    }

    private func japaneseLine(for cue: Cue, in ja: [Cue]) -> String? {
        // Translated cues share timing; otherwise take the one overlapping most.
        let best = ja.max { overlap($0, cue) < overlap($1, cue) }
        guard let b = best, overlap(b, cue) > 0 else { return nil }
        return b.text
    }

    private func overlap(_ a: Cue, _ b: Cue) -> Double { max(0, min(a.end, b.end) - max(a.start, b.start)) }

    // MARK: Subtitles

    var currentRecord: VideoRecord? { bridgeStale ? nil : currentVideoId.flatMap { records[$0] } }

    /// Watchdog: the bridge heartbeats every second while a Short is on screen.
    func checkBridge() {
        guard onShorts, !bridgeStale, Date().timeIntervalSince(lastTickAt) > 3 else { return }
        bridgeStale = true
        appendLog("bridge silent for 3 s: hiding subtitles")
    }

    var currentSourceCueIndex: Int? {
        guard let r = currentRecord else { return nil }
        let cues = r.sourceCues
        if let i = cues.lastIndex(where: { $0.start <= currentTime && currentTime < $0.end }) { return i }
        // Gap after a line with a Japanese word: keep that line up 1.5 s longer so the word can be noticed.
        let targetLines = Set(r.targets.map(\.cueIndex))
        return cues.indices.last { targetLines.contains($0) && cues[$0].end <= currentTime && currentTime < cues[$0].end + 1.5 }
    }

    var currentSourceCue: Cue? { currentSourceCueIndex.map { currentRecord!.sourceCues[$0] } }

    var currentJapaneseCue: Cue? {
        guard let cues = currentRecord?.japaneseCues else { return nil }
        return cues.last { $0.start <= currentTime && currentTime < $0.end }
    }

    /// The swap on the current line, if this line holds one of the video's learning words.
    var currentSwap: SwapMatch? {
        // Ads: no swapped words (marketing copy isn't study material and shouldn't count).
        guard let idx = currentSourceCueIndex, let r = currentRecord, r.isAd != true,
              let target = r.targets.first(where: { $0.cueIndex == idx }) else { return nil }
        return vocab.candidates(in: r.sourceCues[idx].text, allSenses: true).first { $0.entry.id == target.entryId }
    }

    // MARK: Phase 0 stats

    var stats: SpikeStats {
        var s = SpikeStats()
        for id in order {
            guard let r = records[id] else { continue }
            s.videosSeen += 1
            if let info = r.info, !info.tracks.isEmpty { s.withTrackList += 1 }
            if !r.sourceCues.isEmpty { s.withSourceCues += 1 }
            if !r.japaneseCues.isEmpty { s.withJapaneseCues += 1 }
            if r.sourceEmpty == true { s.emptyResponses += 1 }
            if r.usedPot && !r.sourceCues.isEmpty { s.potRecovered += 1 }
            if !r.targets.isEmpty { s.withTargets += 1 }
            s.targetsTotal += r.targets.count
            if r.pickedBy == "jev" { s.pickedByJev += 1 }
        }
        return s
    }

    func exportReport() -> URL? {
        struct Report: Codable {
            let generatedAt: Date
            let stats: SpikeStats
            let videos: [String: VideoRecord]
            let logs: [String]
        }
        let report = Report(generatedAt: Date(), stats: stats, videos: records, logs: logs)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(report) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upscroll-spike-\(Int(Date().timeIntervalSince1970)).json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
