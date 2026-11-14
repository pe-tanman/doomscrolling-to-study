import Foundation

/// One day of feed activity. Japanese time = learning cards + Japanese-audio Shorts + originals + practice.
struct DayStats: Codable, Equatable {
    var scrollSeconds = 0.0
    var japaneseSeconds = 0.0
    var linesHeard = 0
    var shorts = 0
    var japaneseShorts = 0
    var goodStops = 0
    /// Practice screens (World exercises), kept apart from feed time. Optional so older saves still load.
    var practiceSeconds: Double?
    /// Feed seconds with Japanese audio playing (a subset of japaneseSeconds). Optional for older saves.
    var audioSeconds: Double?
}

/// What the current feed session has turned into (shown on the session recap).
struct SessionSnapshot: Equatable {
    var start = Date()
    var scrollSeconds = 0.0
    var japaneseSeconds = 0.0
    var linesHeard = 0
    /// Practice screens (World exercises) during this session, outside the feed.
    var practiceSeconds = 0.0
    var wordsAtStart = 0
    var dotsAtStart = 0
    var stampsAtStart: Set<String> = []
}

/// Coverage rings, places, rewards and impact. Saved as JSON in Application Support.
@MainActor
final class JourneyStore: ObservableObject {
    @Published private(set) var coverage: [String: Set<Skill>] = [:]
    @Published private(set) var lastDot: [String: Date] = [:]
    /// Up to 3 real caption lines per phrase, for phrase cards ("Heard in your feed").
    @Published private(set) var examples: [String: [String]] = [:]
    @Published private(set) var days: [String: DayStats] = [:]
    @Published private(set) var goodStops = 0
    @Published var feedSteps: Set<String> = [] { didSet { save() } }
    @Published private(set) var session = SessionSnapshot()
    @Published private(set) var startedAt = Date()
    /// The learner's personal order of places (set from their LearningPath); empty = curriculum order.
    @Published var placeOrder: [String] = []
    /// Phrases Jev ranked most useful for this learner, first = most useful.
    @Published var phrasePriority: [String] = []

    private struct Saved: Codable {
        var coverage: [String: [Skill]]
        var lastDot: [String: Date]
        var examples: [String: [String]]
        var days: [String: DayStats]
        var goodStops: Int
        var feedSteps: [String]
        var startedAt: Date
    }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journey.json")
    }()
    private var saveTask: Task<Void, Never>?

    init() {
        load()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetJourney") { reset() }
        if args.contains("-demoJourney") { seedDemo() }
        #endif
    }

    #if DEBUG
    /// Screenshots / UI tests: Arrival done, Café halfway, six weeks of rising learning share, a live session.
    func seedDemo() {
        reset()
        let places = Curriculum.places
        for p in places[0].phrases { coverage[p.id] = Set(Skill.allCases) }
        for (i, p) in places[1].phrases.enumerated() {
            coverage[p.id] = i < 2 ? Set(Skill.allCases) : (i < 4 ? [.reading, .listening] : [.reading])
        }
        if let p = places[1].phrases.first { examples[p.id] = ["コーヒーをください、ホットで"] }
        for d in 0..<42 {
            guard let date = Calendar.current.date(byAdding: .day, value: -d, to: Date()) else { continue }
            let scroll = d == 0 ? 840 : Double(1500 + (d * 37) % 900)   // today stays under the 20-min limit
            let share = 0.42 - Double(d) * 0.006
            days[Self.dayKey(date)] = DayStats(scrollSeconds: scroll, japaneseSeconds: scroll * share,
                                               linesHeard: 12 + d % 7, shorts: 60, japaneseShorts: 14 - d / 6,
                                               goodStops: d % 3 == 0 ? 1 : 0)
        }
        goodStops = 9
        startedAt = Calendar.current.date(byAdding: .day, value: -41, to: Date()) ?? Date()
        session = SessionSnapshot(start: Date().addingTimeInterval(-1500), scrollSeconds: 1460, japaneseSeconds: 590,
                                  linesHeard: 23, wordsAtStart: 0, dotsAtStart: max(0, totalDots - 7),
                                  stampsAtStart: Set(stamps.dropLast().map(\.id)))
        save()
    }

    /// Question Lab: set a place's dots directly.
    func debugSet(_ place: Place, skills: Set<Skill>) {
        for p in place.phrases { coverage[p.id] = skills.isEmpty ? nil : skills }
        save()
    }

    /// Question Lab: jump to a place (everything before it done, it and later empty).
    func debugMove(to place: Place) {
        for p in Curriculum.places { debugSet(p, skills: p.index < place.index ? Set(Skill.allCases) : []) }
    }

    /// Question Lab: add feed time to today and the session.
    func debugAddTime(minutes: Double, japaneseShare: Double) {
        let sec = minutes * 60
        session.scrollSeconds += sec
        session.japaneseSeconds += sec * japaneseShare
        updateToday { $0.scrollSeconds += sec; $0.japaneseSeconds += sec * japaneseShare; $0.linesHeard += Int(minutes) }
    }
    #endif

    // MARK: Coverage

    func skills(_ phraseId: String) -> Set<Skill> { coverage[phraseId] ?? [] }

    /// Fill one dot. Returns true when it was new.
    @discardableResult
    func mark(_ phraseId: String, _ skill: Skill) -> Bool {
        var s = coverage[phraseId] ?? []
        guard !s.contains(skill) else { return false }
        s.insert(skill)
        coverage[phraseId] = s
        lastDot[phraseId] = Date()
        saveSoon()
        return true
    }

    func noteExample(_ phraseId: String, line: String) {
        var e = examples[phraseId] ?? []
        guard !e.contains(line), line.count < 80 else { return }
        e.insert(line, at: 0)
        examples[phraseId] = Array(e.prefix(3))
        saveSoon()
    }

    var totalDots: Int { coverage.values.reduce(0) { $0 + $1.count } }
    func isFull(_ phraseId: String) -> Bool { skills(phraseId).count == Skill.allCases.count }
    func phrasesDone(_ place: Place) -> Int { place.phrases.filter { isFull($0.id) }.count }
    func isComplete(_ place: Place) -> Bool { phrasesDone(place) == place.phrases.count }

    /// Every place in this learner's own order (personal path first, any others after in curriculum order).
    var orderedPlaces: [Place] {
        guard !placeOrder.isEmpty else { return Curriculum.places }
        let byId = Dictionary(uniqueKeysWithValues: Curriculum.places.map { ($0.id, $0) })
        let first = placeOrder.compactMap { byId[$0] }
        let seen = Set(first.map(\.id))
        return first + Curriculum.places.filter { !seen.contains($0.id) }
    }

    /// The first place on the personal path that isn't complete.
    var currentPlace: Place { orderedPlaces.first { !isComplete($0) } ?? orderedPlaces.last! }

    enum PlaceState { case done, current, locked }
    func state(_ place: Place) -> PlaceState {
        if isComplete(place) { return .done }
        return place.id == currentPlace.id ? .current : .locked
    }

    /// Missing dots in a place, most-missing first; ties broken by the oldest last dot.
    func gaps(_ place: Place) -> [(phrase: Phrase, missing: [Skill])] {
        place.phrases.compactMap { p -> (Phrase, [Skill])? in
            let m = Skill.allCases.filter { !skills(p.id).contains($0) }
            return m.isEmpty ? nil : (p, m)
        }
        .sorted { a, b in
            if a.1.count != b.1.count { return a.1.count > b.1.count }
            // Same number of gaps: the phrase Jev ranked more useful for this learner first.
            let pa = phrasePriority.firstIndex(of: a.0.id) ?? Int.max, pb = phrasePriority.firstIndex(of: b.0.id) ?? Int.max
            if pa != pb { return pa < pb }
            return (lastDot[a.0.id] ?? .distantPast) < (lastDot[b.0.id] ?? .distantPast)
        }
    }

    func gapCount(_ place: Place) -> Int { gaps(place).reduce(0) { $0 + $1.missing.count } }
    func gapCount(_ place: Place, skill: Skill) -> Int { gaps(place).filter { $0.missing.contains(skill) }.count }

    // MARK: Rewards

    func earned(_ c: CanDo) -> Bool { c.phraseIds.allSatisfy { isFull($0) } }
    var stamps: [CanDo] { Curriculum.places.flatMap(\.canDos).filter { earned($0) } }
    var souvenirs: [Place] { Curriculum.places.filter { isComplete($0) } }

    // MARK: Time & impact

    static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    var today: DayStats { days[Self.dayKey(Date())] ?? DayStats() }

    private func updateToday(_ f: (inout DayStats) -> Void) {
        let k = Self.dayKey(Date())
        var d = days[k] ?? DayStats()
        f(&d)
        days[k] = d
        saveSoon()
    }

    /// Seconds spent in the feed; `japanese` when that time was Japanese (audio, a card, an original).
    func addFeedTime(_ seconds: Double, japanese: Bool, audio: Bool = false) {
        guard seconds > 0, seconds < 5 else { return }
        session.scrollSeconds += seconds
        if japanese { session.japaneseSeconds += seconds }
        updateToday {
            $0.scrollSeconds += seconds
            if japanese { $0.japaneseSeconds += seconds }
            if audio { $0.audioSeconds = ($0.audioSeconds ?? 0) + seconds }
        }
    }

    /// Japanese time spent outside the feed (practice screens).
    func addPracticeTime(_ seconds: Double) {
        guard seconds > 0, seconds < 600 else { return }
        session.practiceSeconds += seconds
        // Not added to japaneseSeconds: that's the share of *scrolling* that became Japanese.
        updateToday { $0.practiceSeconds = ($0.practiceSeconds ?? 0) + seconds }
    }

    func heardLine() { session.linesHeard += 1; updateToday { $0.linesHeard += 1 } }
    func shortStarted(japaneseAudio: Bool) { updateToday { $0.shorts += 1; if japaneseAudio { $0.japaneseShorts += 1 } } }

    func startSession(words: Int) {
        session = SessionSnapshot(start: Date(), wordsAtStart: words, dotsAtStart: totalDots, stampsAtStart: Set(stamps.map(\.id)))
    }

    /// The mascot's gifts, one per good stop, in order (cycles after the last).
    static let gifts: [(emoji: String, name: String)] = [
        ("🍡", "a dango snack"), ("🎐", "a wind chime"), ("🧣", "a sakura scarf"), ("🍙", "an onigiri"),
        ("🎏", "a carp streamer"), ("🍵", "a cup of matcha"), ("🏮", "a paper lantern"), ("🎴", "a hanafuda card"),
    ]
    /// The gift earned by good stop number `n` (1-based).
    static func gift(_ n: Int) -> (emoji: String, name: String) { gifts[(max(1, n) - 1) % gifts.count] }

    func goodStop() {
        Rewards.shared.earnFreeze("good stop")
        goodStops += 1
        updateToday { $0.goodStops += 1 }
    }

    /// Sum over the last `n` days (today included).
    func total(lastDays n: Int) -> DayStats {
        var t = DayStats()
        for i in 0..<n {
            guard let d = Calendar.current.date(byAdding: .day, value: -i, to: Date()), let s = days[Self.dayKey(d)] else { continue }
            t.scrollSeconds += s.scrollSeconds; t.japaneseSeconds += s.japaneseSeconds; t.linesHeard += s.linesHeard
            t.shorts += s.shorts; t.japaneseShorts += s.japaneseShorts; t.goodStops += s.goodStops
            t.audioSeconds = (t.audioSeconds ?? 0) + (s.audioSeconds ?? 0)
        }
        return t
    }

    /// Every recorded day (not counted from startedAt, which could be later than old history and made
    /// "since you started" smaller than "this week").
    var allTime: DayStats {
        var t = DayStats()
        for s in days.values {
            t.scrollSeconds += s.scrollSeconds; t.japaneseSeconds += min(s.japaneseSeconds, s.scrollSeconds); t.linesHeard += s.linesHeard
            t.shorts += s.shorts; t.japaneseShorts += s.japaneseShorts; t.goodStops += s.goodStops
            t.audioSeconds = (t.audioSeconds ?? 0) + (s.audioSeconds ?? 0)
        }
        return t
    }

    /// Japanese share per week, oldest first (last `weeks` weeks).
    func weeklyShare(weeks: Int = 6) -> [Double] {
        (0..<weeks).reversed().map { w in
            var scroll = 0.0, ja = 0.0
            for i in 0..<7 {
                guard let d = Calendar.current.date(byAdding: .day, value: -(w * 7 + i), to: Date()), let s = days[Self.dayKey(d)] else { continue }
                scroll += s.scrollSeconds; ja += s.japaneseSeconds
            }
            return scroll > 0 ? ja / scroll : 0
        }
    }

    /// Share of watched Shorts with Japanese audio, last 7 days.
    var japaneseFeedShare: Double { let w = total(lastDays: 7); return w.shorts > 0 ? Double(w.japaneseShorts) / Double(w.shorts) : 0 }

    func reset() {
        coverage = [:]; lastDot = [:]; examples = [:]; days = [:]; goodStops = 0; feedSteps = []; startedAt = Date()
        save()
    }

    // MARK: Persistence

    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    // MARK: Cloud sync

    struct CloudPart: Codable {
        var coverage: [String: [Skill]]; var lastDot: [String: Date]; var examples: [String: [String]]
        var days: [String: DayStats]; var goodStops: Int; var feedSteps: [String]; var startedAt: Date
    }

    func cloudExport() -> CloudPart {
        CloudPart(coverage: coverage.mapValues { Array($0) }, lastDot: lastDot, examples: examples, days: days,
                  goodStops: goodStops, feedSteps: Array(feedSteps), startedAt: startedAt)
    }

    /// Merge a cloud copy: coverage dots and steps are combined, per-day stats keep the bigger day, totals the max.
    func cloudMerge(_ c: CloudPart) {
        for (id, skills) in c.coverage { coverage[id, default: []].formUnion(skills) }
        for (id, d) in c.lastDot where d > (lastDot[id] ?? .distantPast) { lastDot[id] = d }
        for (id, ex) in c.examples { examples[id] = Array(NSOrderedSet(array: (examples[id] ?? []) + ex).array.compactMap { $0 as? String }.prefix(3)) }
        for (day, r) in c.days {
            guard let l = days[day] else { days[day] = r; continue }
            if r.scrollSeconds > l.scrollSeconds { days[day] = r }
        }
        goodStops = max(goodStops, c.goodStops)
        feedSteps.formUnion(c.feedSteps)
        startedAt = min(startedAt, c.startedAt)
        save()
    }

    func save() {
        let s = Saved(coverage: coverage.mapValues { Array($0) }, lastDot: lastDot, examples: examples, days: days,
                      goodStops: goodStops, feedSteps: Array(feedSteps), startedAt: startedAt)
        if let data = try? JSONEncoder().encode(s) { try? data.write(to: url, options: .atomic) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        coverage = s.coverage.mapValues { Set($0) }
        lastDot = s.lastDot; examples = s.examples; days = s.days; goodStops = s.goodStops
        feedSteps = Set(s.feedSteps); startedAt = s.startedAt
    }
}
