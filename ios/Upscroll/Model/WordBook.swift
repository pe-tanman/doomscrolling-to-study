import Foundation

/// Where the learner met a word: the clip and the line it appeared in.
struct WordContext: Codable, Hashable {
    let videoId: String
    let title: String
    let line: String
    let japaneseLine: String?
    let date: Date
}

struct WordProgress: Codable, Identifiable {
    let id: String              // VocabEntry.id
    var firstSeen: Date
    var lastSeen: Date
    var timesSeen = 0
    var timesHeard = 0
    var correct = 0
    var wrong = 0
    /// 0…5 for the dots in the UI, from `stability`. 5 = known.
    var box = 0
    var due: Date
    var contexts: [WordContext] = []
    /// Forgetting curve (see Memory): days until recall drops to 90%, and when it was last reviewed.
    /// Optional so older saves still load; missing values are derived from `box`.
    var stability: Double?
    var lastReview: Date?
    var lapses: Int?

    var isKnown: Bool { box >= 5 }
    /// Learned = the schedule says it lasts 3+ days AND at least one answer confirmed it.
    /// "I knew it" alone (a self-report) never counts.
    var isLearned: Bool { (stability ?? Memory.stability(fromBox: box)) >= 3 && correct > 0 }
    /// Recall probability right now.
    var recallNow: Double {
        Memory.recall(stability: stability ?? Memory.stability(fromBox: box),
                      elapsedDays: Date().timeIntervalSince(lastReview ?? lastSeen) / 86400)
    }
    /// Due when the forgetting curve says recall has dropped to 90% (known words too, just rarely).
    var isDue: Bool { due <= Date() }
    /// How hard to ask: 0 not answered right yet (recognize), 1 getting there (choose / build), 2 strong (produce).
    var reviewStage: Int {
        if correct == 0 { return 0 }
        let s = stability ?? Memory.stability(fromBox: box)
        return (correct >= 3 && s >= 3) || box >= 3 ? 2 : 1
    }
}

enum WordStatus: String, CaseIterable, Identifiable {
    case all = "All", learning = "Learning", due = "Due", known = "Known"
    var id: String { rawValue }
}

/// The learner's collection: every word met in the feed, its review schedule and daily activity.
/// Saved as JSON in Application Support.
@MainActor
final class WordBook: ObservableObject {
    @Published private(set) var words: [String: WordProgress] = [:]
    @Published private(set) var activeDays: Set<String> = []
    /// Closure after leaving Review: "You reviewed 23 (20 right) · 7 left for later". Not saved.
    @Published var lastReviewSummary: String? { didSet { lastReviewAt = lastReviewSummary == nil ? nil : Date() } }
    private(set) var lastReviewAt: Date?
    /// The summary only while it's fresh (it describes one review visit, not the whole day).
    var freshReviewSummary: String? {
        guard let s = lastReviewSummary, let at = lastReviewAt, Date().timeIntervalSince(at) < 15 * 60 else { return nil }
        return s
    }


    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wordbook.json")
    }()

    init() { load() }

    // MARK: Events

    func recordEncounter(_ e: VocabEntry, context: WordContext) {
        let now = Date()
        var p = words[e.id] ?? WordProgress(id: e.id, firstSeen: now, lastSeen: now, due: now)
        p.lastSeen = now
        p.timesSeen += 1
        // First meeting starts the forgetting curve: check again in ~10 minutes.
        // Later meetings don't move the schedule; only answering does.
        if p.stability == nil && p.timesSeen == 1 {
            schedule(&p, stability: Memory.firstStability, at: now)
        }
        if !p.contexts.contains(where: { $0.videoId == context.videoId && $0.line == context.line }) {
            p.contexts.insert(context, at: 0)
            if p.contexts.count > 5 { p.contexts.removeLast(p.contexts.count - 5) }
        }
        words[e.id] = p
        markActive(now)
        save()
    }

    func recordHeard(_ id: String) {
        guard var p = words[id] else { return }
        p.timesHeard += 1
        words[id] = p
        save()
    }

    /// `easy`: answered right quickly — the word was easy to recall, so it's pushed much further out.
    func recordAnswer(_ id: String, correct: Bool, easy: Bool = false) {
        let now = Date()
        var p = words[id] ?? WordProgress(id: id, firstSeen: now, lastSeen: now, due: now)
        let s = p.stability ?? Memory.stability(fromBox: p.box)
        let elapsed = now.timeIntervalSince(p.lastReview ?? p.lastSeen) / 86400
        let grade: Memory.Grade = !correct ? .again : (easy ? .easy : .good)
        if correct { p.correct += 1; Rewards.shared.correctAnswer() } else { p.wrong += 1; p.lapses = (p.lapses ?? 0) + 1 }
        schedule(&p, stability: Memory.next(stability: s, elapsedDays: elapsed, grade: grade, lapses: p.lapses ?? 0), at: now)
        words[id] = p
        markActive(now)
        save()
    }

    /// "I knew it": treat as known — it comes back once in a while (when the curve says so) to make sure.
    /// Relearn: back to the start of the curve.
    /// "I knew it" on a new-word card: a claim, not proof. Check it in 2 days (below the 3-day "learned" bar);
    /// a right answer then pushes it out like any other review.
    func claimKnown(_ id: String) {
        guard var p = words[id] else { return }
        schedule(&p, stability: max(p.stability ?? 0, 2), at: Date())
        words[id] = p
        save()
    }

    /// Skip ticket: push a word to tomorrow without counting a miss.
    func postpone(_ id: String, days: Double = 1) {
        guard var p = words[id] else { return }
        p.due = Date().addingTimeInterval(days * 86400)
        words[id] = p
        save()
    }

    func markKnown(_ id: String, _ known: Bool = true) {
        guard var p = words[id] else { return }
        schedule(&p, stability: known ? max(p.stability ?? 0, Memory.knownStability) : Memory.firstStability, at: Date())
        words[id] = p
        save()
    }

    private func schedule(_ p: inout WordProgress, stability s: Double, at now: Date) {
        p.stability = s
        p.lastReview = now
        p.due = now.addingTimeInterval(s * 86400)
        p.box = Memory.box(stability: s)
    }

    #if DEBUG
    func seedForTesting(_ e: VocabEntry, correct: Int, context: WordContext) {
        var p = WordProgress(id: e.id, firstSeen: context.date, lastSeen: context.date, due: .distantPast)
        p.timesSeen = 1
        p.correct = correct
        p.box = correct
        p.stability = correct > 0 ? 1 : Memory.firstStability
        p.lastReview = context.date
        p.contexts = [context]
        words[e.id] = p
    }
    #endif

    #if DEBUG
    /// Question Lab: every collected word is due now (review / recall cards fire).
    func debugMakeAllDue() {
        for k in words.keys { words[k]?.due = Date().addingTimeInterval(-60); words[k]?.lastSeen = Date().addingTimeInterval(-3600) }
        save()
    }
    #endif

    func reset() {
        words = [:]
        activeDays = []
        save()
    }

    // MARK: Queries

    func progress(_ id: String) -> WordProgress? { words[id] }

    func list(_ status: WordStatus) -> [WordProgress] {
        let all = words.values.sorted { $0.lastSeen > $1.lastSeen }
        switch status {
        case .all: return all
        case .learning: return all.filter { !$0.isKnown }
        case .due: return all.filter(\.isDue)
        case .known: return all.filter(\.isKnown)
        }
    }

    /// Per JLPT level: words met, and words learned (got right a few times: Leitner box ≥ 3).
    func levelProgress(_ level: Int, vocab: VocabStore) -> (met: Int, learned: Int, total: Int) {
        var met = 0, learned = 0
        for p in words.values where vocab.byId[p.id]?.level == level {
            met += 1
            if p.box >= 3 { learned += 1 }
        }
        return (met, learned, vocab.countByLevel[level] ?? 0)
    }

    /// Words learned = you would still recall them in 3 days (forgetting-curve stability ≥ 3 days).
    /// This is the number shown on Home and in Progress.
    var learnedCount: Int { words.values.filter(\.isLearned).count }
    func learnedCount(level: Int, vocab: VocabStore) -> Int {
        words.values.filter { $0.isLearned && vocab.byId[$0.id]?.level == level }.count
    }
    /// New words first met since `date` (for the session recap).
    func newWords(since date: Date) -> Int { words.values.filter { $0.firstSeen >= date }.count }

    var dueWords: [WordProgress] { words.values.filter(\.isDue).sorted { $0.due < $1.due } }
    var knownCount: Int { words.values.filter(\.isKnown).count }

    var metToday: [WordProgress] {
        let cal = Calendar.current
        return words.values.filter { cal.isDateInToday($0.lastSeen) }.sorted { $0.lastSeen > $1.lastSeen }
    }

    var newToday: Int {
        words.values.filter { Calendar.current.isDateInToday($0.firstSeen) }.count
    }

    /// Consecutive active days ending today (or yesterday, so the streak isn't lost before you scroll).
    var streak: Int {
        // Days covered by a streak freeze count as active.
        let days = activeDays.union(Rewards.shared.frozenDays)
        var day = Date()
        if !days.contains(Self.key(day)) {
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        var n = 0
        while days.contains(Self.key(day)) {
            n += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }

    /// Last 7 days, oldest first, for the activity strip.
    var lastWeek: [(label: String, active: Bool, isToday: Bool)] {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return (0..<7).reversed().map { back in
            let d = Calendar.current.date(byAdding: .day, value: -back, to: Date())!
            return (f.string(from: d), activeDays.contains(Self.key(d)), back == 0)
        }
    }

    // MARK: Cloud sync

    struct CloudPart: Codable { var words: [String: WordProgress]; var activeDays: Set<String> }

    func cloudExport() -> CloudPart { CloudPart(words: words, activeDays: activeDays) }

    /// Merge a cloud copy: per word, the copy reviewed or seen most recently wins; active days are combined.
    func cloudMerge(_ c: CloudPart) {
        for (id, remote) in c.words {
            guard let local = words[id] else { words[id] = remote; continue }
            let lt = max(local.lastReview ?? .distantPast, local.lastSeen)
            let rt = max(remote.lastReview ?? .distantPast, remote.lastSeen)
            if rt > lt { words[id] = remote }
        }
        activeDays.formUnion(c.activeDays)
        save()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var words: [String: WordProgress]
        var activeDays: Set<String>
    }

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func markActive(_ d: Date) { activeDays.insert(Self.key(d)) }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let s = try? dec.decode(Snapshot.self, from: data) {
            words = s.words
            activeDays = s.activeDays
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(Snapshot(words: words, activeDays: activeDays)) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
