import Foundation

/// Why someone is learning. Chosen in onboarding (and Settings); it steers their personal path.
enum LearningGoal: String, CaseIterable, Identifiable, Codable {
    case travel, anime, friends, work, culture
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .travel: return "✈️"
        case .anime: return "🎮"
        case .friends: return "💬"
        case .work: return "💼"
        case .culture: return "🍜"
        }
    }

    var title: String {
        switch self {
        case .travel: return "Travel"
        case .anime: return "Anime & games"
        case .friends: return "Friends"
        case .work: return "Work & study"
        case .culture: return "Food & culture"
        }
    }

    /// Offline fallback order of places for this goal (Jev's order replaces it when the server answers).
    var defaultOrder: [String] {
        switch self {
        case .travel: return ["arrival", "cafe", "station", "konbini", "ramen", "shrine", "castle"]
        case .anime: return ["arrival", "cafe", "shrine", "konbini", "ramen", "station", "castle"]
        case .friends: return ["arrival", "cafe", "shrine", "ramen", "konbini", "station", "castle"]
        case .work: return ["arrival", "cafe", "station", "castle", "konbini", "ramen", "shrine"]
        case .culture: return ["arrival", "cafe", "konbini", "shrine", "ramen", "station", "castle"]
        }
    }
}

/// A learner's own curriculum: the order of places, the skill the feed pushes, phrases that matter most.
struct LearningPath: Codable, Equatable {
    var goal: String
    var order: [String]
    var next: String?
    var focus: Skill?
    var phrasePriority: [String]
    /// "jev" when TypeSafe Jev decided it, "rules" for the offline goal-based fallback.
    var source: String
    var updated: Date
    /// What the path was built from (goal + finished places); a change triggers a rebuild.
    var signature: String
}

/// Builds and keeps the personal path. Asks Jev at most every few hours, or when the goal
/// or the set of finished places changes. Falls back to the goal's default order offline.
@MainActor
final class PathStore: ObservableObject {
    static let shared = PathStore()
    @Published private(set) var path: LearningPath?
    @Published private(set) var refreshing = false
    private let key = "learningPath.v1"

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode(LearningPath.self, from: d) { path = p }
    }

    var focus: Skill? { path?.focus }

    /// Apply the current path (or the goal's default) to the journey right away, then refresh if stale.
    func update(session: FeedSession, journey: JourneyStore, wordBook: WordBook, force: Bool = false) {
        let goal = LearningGoal(rawValue: session.settings.goal) ?? .culture
        let sig = Self.signature(goal: goal, journey: journey)
        if path == nil || path?.goal != goal.rawValue {
            set(LearningPath(goal: goal.rawValue, order: goal.defaultOrder, next: nil, focus: nil, phrasePriority: [],
                             source: "rules", updated: .distantPast, signature: ""), journey: journey)
        } else if let p = path {
            apply(p, to: journey)
        }
        let stale = path.map { $0.signature != sig || Date().timeIntervalSince($0.updated) > 6 * 3600 } ?? true
        guard force || stale, !refreshing, LessonClient.baseURL != nil else { return }
        refreshing = true
        let req = Self.request(goal: goal, session: session, journey: journey, wordBook: wordBook)
        Task {
            defer { refreshing = false }
            do {
                let r = try await LessonClient.path(req)
                // Places Jev didn't mention keep the goal order after the ones it did.
                let known = Set(r.order)
                let order = r.order + goal.defaultOrder.filter { !known.contains($0) }
                set(LearningPath(goal: goal.rawValue, order: order, next: r.next, focus: r.focus.flatMap(Skill.init(rawValue:)),
                                 phrasePriority: r.phrasePriority, source: "jev", updated: Date(), signature: sig), journey: journey)
                session.appendLogPublic("path (jev): next \(r.next ?? "-") focus \(r.focus ?? "-")")
            } catch {
                session.appendLogPublic("path: \(error.localizedDescription)")
            }
        }
    }

    private func set(_ p: LearningPath, journey: JourneyStore) {
        path = p
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: key) }
        apply(p, to: journey)
    }

    private func apply(_ p: LearningPath, to journey: JourneyStore) {
        if journey.placeOrder != p.order { journey.placeOrder = p.order }
        if journey.phrasePriority != p.phrasePriority { journey.phrasePriority = p.phrasePriority }
    }

    static func signature(goal: LearningGoal, journey: JourneyStore) -> String {
        goal.rawValue + "|" + Curriculum.places.filter { journey.isComplete($0) }.map(\.id).joined(separator: ",")
    }

    static func request(goal: LearningGoal, session: FeedSession, journey: JourneyStore, wordBook: WordBook) -> PathRequest {
        // Interests: titles of recently watched Shorts (what they actually scroll).
        let titles = session.order.suffix(40).reversed().compactMap { session.records[$0]?.info?.title }.filter { !$0.isEmpty }
        let interests = Array(NSOrderedSet(array: titles).array.compactMap { $0 as? String }.prefix(12))
        var skills: [String: PathRequest.SkillResult] = [:]
        let right = wordBook.words.values.reduce(0) { $0 + $1.correct }
        let wrong = wordBook.words.values.reduce(0) { $0 + $1.wrong }
        for s in Skill.allCases {
            let dots = journey.coverage.values.filter { $0.contains(s) }.count
            // Word answers are reading/listening checks; the other skills only have their dots.
            skills[s.rawValue] = .init(right: s == .reading ? right : 0, wrong: s == .reading ? wrong : 0, dots: dots)
        }
        let places = Curriculum.places.map { p in
            PathRequest.PlaceDTO(id: p.id, name: p.name, summary: p.summary, canDos: p.canDos.map(\.title),
                                 done: journey.phrasesDone(p), total: p.phrases.count)
        }
        // Phrases of the places Jev could pick next.
        let open = Curriculum.places.filter { !journey.isComplete($0) }.prefix(3)
        let phrases = open.flatMap { pl in pl.phrases.filter { !journey.isFull($0.id) }.map {
            PathRequest.PhraseDTO(id: $0.id, place: pl.id, meaning: $0.meaning, example: $0.example)
        } }
        return PathRequest(goal: goal.rawValue, level: "N\(session.settings.jlptLevel)", wordsLearned: wordBook.learnedCount,
                           interests: interests, skills: skills,
                           speakingOff: !session.settings.speakingInFeed || SpeechCheck.permissionDenied,
                           stage: session.ladderStage.title.lowercased(), grammarKnown: GrammarBook.shared.knownTitles,
                           places: places, phrases: Array(phrases.prefix(20)))
    }
}
