import Foundation

/// A special Upscroll lesson: a real YouTube Short made for learners, played inside the feed,
/// with checkpoints that pause it for a card. The catalog comes from the lesson server
/// (`server/lib/lessons.json` → GET /api/lessons), so new lessons need no app update;
/// `Resources/lessons.json` is the bundled copy used offline.
struct LessonVideo: Codable, Identifiable, Hashable {
    struct Checkpoint: Codable, Hashable {
        /// Seconds into the Short.
        let at: Double
        /// "phrase" (curriculum phrase + skill) or "word" (vocab entry).
        let kind: String
        var phraseId: String?
        var entryId: String?
        var skill: String?
    }
    let id: String
    let youtubeId: String
    let title: String
    /// Curriculum place it belongs to (nil = any).
    var place: String?
    /// Learner goals it suits (empty = everyone).
    var goals: [String] = []
    var level: Int = 0
    var enabled: Bool?
    var checkpoints: [Checkpoint] = []

    var url: URL { URL(string: "https://m.youtube.com/shorts/\(youtubeId)")! }
    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(youtubeId)/hqdefault.jpg")! }
    var isLive: Bool { enabled != false && !youtubeId.isEmpty && !youtubeId.hasPrefix("REPLACE") }

    enum CodingKeys: String, CodingKey { case id, youtubeId, title, place, goals, level, enabled, checkpoints }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        youtubeId = try c.decode(String.self, forKey: .youtubeId)
        title = try c.decode(String.self, forKey: .title)
        place = try c.decodeIfPresent(String.self, forKey: .place)
        goals = try c.decodeIfPresent([String].self, forKey: .goals) ?? []
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        checkpoints = (try c.decodeIfPresent([Checkpoint].self, forKey: .checkpoints) ?? []).sorted { $0.at < $1.at }
    }
    init(id: String, youtubeId: String, title: String, place: String?, goals: [String] = [], checkpoints: [Checkpoint]) {
        self.id = id; self.youtubeId = youtubeId; self.title = title; self.place = place; self.goals = goals
        self.enabled = true; self.checkpoints = checkpoints
    }
}

struct LessonCatalog: Codable {
    var version: Int
    var lessons: [LessonVideo]
}

/// The lesson catalog plus what this learner has watched.
@MainActor
final class LessonLibrary: ObservableObject {
    static let shared = LessonLibrary()
    @Published private(set) var lessons: [LessonVideo] = []
    @Published private(set) var watched: Set<String> = []
    private let watchedKey = "lessons.watched"
    private let cacheKey = "lessons.catalog"

    private init() {
        watched = Set(UserDefaults.standard.stringArray(forKey: watchedKey) ?? [])
        if let d = UserDefaults.standard.data(forKey: cacheKey), let c = try? JSONDecoder().decode(LessonCatalog.self, from: d) {
            lessons = c.lessons.filter(\.isLive)
        } else if let u = Bundle.main.url(forResource: "lessons", withExtension: "json"),
                  let d = try? Data(contentsOf: u), let c = try? JSONDecoder().decode(LessonCatalog.self, from: d) {
            lessons = c.lessons.filter(\.isLive)
        }
        #if DEBUG
        // `-demoLesson`: a stand-in lesson on a known Short, to try the lesson frame before real videos exist.
        if ProcessInfo.processInfo.arguments.contains("-demoLesson") {
            lessons.insert(LessonVideo(id: "demo", youtubeId: "SyxBTFf0U1E", title: "Demo lesson: こんにちは", place: "arrival",
                                       checkpoints: [.init(at: 3, kind: "phrase", phraseId: "hello", skill: "listening"),
                                                     .init(at: 8, kind: "word", entryId: "cat")]), at: 0)
            watched = []
        }
        #endif
    }

    /// Fetch the live catalog (new lessons appear without an app update).
    func refresh() async {
        guard let c = try? await LessonClient.lessons() else { return }
        let live = c.lessons.filter(\.isLive)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoLesson") { return }
        #endif
        lessons = live
        if let d = try? JSONEncoder().encode(LessonCatalog(version: c.version, lessons: live)) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }

    func lesson(youtubeId: String?) -> LessonVideo? { youtubeId.flatMap { id in lessons.first { $0.youtubeId == id } } }

    func markWatched(_ l: LessonVideo) {
        guard !watched.contains(l.id) else { return }
        watched.insert(l.id)
        UserDefaults.standard.set(Array(watched), forKey: watchedKey)
    }

    /// The best unwatched lesson for this learner now: their current place first, then their goal, then anything.
    func next(place: String, goal: String) -> LessonVideo? {
        let fresh = lessons.filter { !watched.contains($0.id) }
        func suits(_ l: LessonVideo) -> Bool { l.goals.isEmpty || l.goals.contains(goal) }
        return fresh.first { $0.place == place && suits($0) }
            ?? fresh.first { $0.place == nil && suits($0) }
            ?? fresh.first { suits($0) }
    }

    /// Lessons in the learner's path order (for the Home shelf).
    func ordered(placeOrder: [String]) -> [LessonVideo] {
        lessons.sorted { a, b in
            let ia = a.place.flatMap { placeOrder.firstIndex(of: $0) } ?? Int.max
            let ib = b.place.flatMap { placeOrder.firstIndex(of: $0) } ?? Int.max
            return ia < ib
        }
    }
}
