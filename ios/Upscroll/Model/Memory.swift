import Foundation

/// Forgetting curve for one word (a small FSRS-style model).
///
/// Recall probability decays over time: R(t) = 0.9 ^ (t / S), where S ("stability", in days) is the time
/// until recall drops to 90%. A word is due when R falls to 90%, i.e. S days after the last review.
/// - Remembered: S grows (more when it was easy, and more the longer it had been since the last review —
///   reviewing too early teaches little, the spacing effect).
/// - Forgotten: S shrinks, so it comes back soon.
/// Until a word is due it is not shown again: no repeats of words you still remember.
enum Memory {
    enum Grade { case again, good, easy }

    static let targetRecall = 0.9
    /// After the first meeting: check again in ~10 minutes (short-term step).
    static let firstStability = 10.0 / 1440
    /// Stability (days) at which a word counts as known. It still comes back once R decays to 90%.
    static let knownStability = 30.0
    /// A correct answer this fast (seconds) counts as easy recall.
    static let easySeconds = 3.0

    /// Probability of recalling the word now.
    static func recall(stability s: Double, elapsedDays t: Double) -> Double {
        pow(targetRecall, max(0, t) / max(s, 1e-6))
    }

    /// New stability after a review.
    static func next(stability s: Double, elapsedDays t: Double, grade: Grade, lapses: Int) -> Double {
        switch grade {
        case .again:
            return max(firstStability, s * 0.3)
        case .good, .easy:
            // Still in the short-term phase (first day): graduate straight to days.
            if s < 1 { return grade == .easy ? 4 : 1 }
            // How much had been forgotten (1 = reviewed on time or late, ~0 = reviewed far too early).
            let spacing = min(1, t / s)
            let growth = grade == .easy ? 3.0 : 1.5
            // Words that were forgotten before grow more slowly.
            return s * (1 + growth * spacing / (1 + 0.2 * Double(lapses)))
        }
    }

    /// Five dots in the UI: 0 = just met … 5 = known.
    static func box(stability s: Double) -> Int {
        switch s {
        case ..<1: return 0
        case ..<3: return 1
        case ..<7: return 2
        case ..<14: return 3
        case ..<knownStability: return 4
        default: return 5
        }
    }

    /// Older saves only had Leitner boxes: map each box to a stability.
    static func stability(fromBox box: Int) -> Double {
        [firstStability, 1, 2, 4, 8, knownStability][max(0, min(5, box))]
    }
}
