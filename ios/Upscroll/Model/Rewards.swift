import Foundation

/// Rewards you can actually use (not just collect):
/// - Streak freeze (snowflake icon): covers a missed day automatically, so one busy day doesn't reset the streak.
/// - Skip ticket (skip icon): skip a quiz card without it counting as a miss (the word comes back tomorrow).
/// Earned by healthy habits: a good stop at the daily limit, correct answers, streak milestones,
/// and once for signing in (progress saved to the cloud).
@MainActor
final class Rewards: ObservableObject {
    static let shared = Rewards()

    static let maxFreezes = 3
    static let maxSkips = 5
    static let correctPerSkip = 10

    @Published private(set) var freezes: Int
    @Published private(set) var skips: Int
    /// Days covered by a freeze ("yyyy-MM-dd"); they count as active for the streak.
    @Published private(set) var frozenDays: Set<String>
    /// Last thing earned, for a small "you got…" toast.
    /// Shown with the app's reward icon (RewardIcon), never emoji.
    @Published var lastEarned: RewardNote?
    private var correctSinceSkip: Int
    private var streakMilestones: Set<Int>

    private let d = UserDefaults.standard
    private init() {
        freezes = d.object(forKey: "rw.freezes") as? Int ?? 1          // one to start, so it's discoverable
        skips = d.object(forKey: "rw.skips") as? Int ?? 2
        frozenDays = Set(d.stringArray(forKey: "rw.frozen") ?? [])
        correctSinceSkip = d.integer(forKey: "rw.correct")
        streakMilestones = Set((d.array(forKey: "rw.milestones") as? [Int]) ?? [])
    }

    private func save() {
        d.set(freezes, forKey: "rw.freezes"); d.set(skips, forKey: "rw.skips")
        d.set(Array(frozenDays), forKey: "rw.frozen"); d.set(correctSinceSkip, forKey: "rw.correct")
        d.set(Array(streakMilestones), forKey: "rw.milestones")
    }

    // MARK: Earning

    func earnFreeze(_ why: String) {
        guard freezes < Self.maxFreezes else { return }
        freezes += 1; lastEarned = RewardNote(icon: .freeze, text: "+1 streak freeze · \(why)"); save()
    }

    func correctAnswer() {
        correctSinceSkip += 1
        if correctSinceSkip >= Self.correctPerSkip {
            correctSinceSkip = 0
            if skips < Self.maxSkips { skips += 1; lastEarned = RewardNote(icon: .skip, text: "+1 skip ticket · \(Self.correctPerSkip) right answers") }
        }
        save()
    }

    /// 7, 30, 100-day streaks each give a freeze once.
    func checkStreak(_ streak: Int) {
        for m in [7, 30, 100] where streak >= m && !streakMilestones.contains(m) {
            streakMilestones.insert(m); earnFreeze("\(m)-day streak")
        }
        save()
    }

    // MARK: Sign-in gift

    static let signInFreezes = 1
    static let signInSkips = 2
    /// Recorded with the streak milestones (synced to the cloud), so the gift is given once per account,
    /// not again after signing out and in, or on a second iPhone.
    private static let signInMarker = 0
    var signInGiftClaimed: Bool { streakMilestones.contains(Self.signInMarker) }
    /// Plain words (for VoiceOver); on screen use RewardText.signInGift(), which shows the app's icons.
    static var signInGiftText: String { "+\(signInFreezes) streak freeze and +\(signInSkips) skip tickets" }

    /// Call after signing in and syncing (so a gift claimed on another device is already known).
    func claimSignInGift() {
        guard !signInGiftClaimed else { return }
        streakMilestones.insert(Self.signInMarker)
        freezes = min(Self.maxFreezes, freezes + Self.signInFreezes)
        skips = min(Self.maxSkips, skips + Self.signInSkips)
        lastEarned = RewardNote(icon: .gift, text: "Signed in: \(Self.signInGiftText)")
        save()
    }

    var progressToSkip: Double { Double(correctSinceSkip) / Double(Self.correctPerSkip) }

    // MARK: Using

    func useSkip() -> Bool {
        guard skips > 0 else { return false }
        skips -= 1
        lastEarned = RewardNote(icon: .skip, text: "Skip ticket used · \(skips) left · no miss counted · +1 per \(Self.correctPerSkip) right answers")
        save(); return true
    }

    /// Called at launch: missed days between the last active day and today are covered by freezes, if enough.
    func applyFreezes(activeDays: Set<String>, key: (Date) -> String) {
        let cal = Calendar.current
        let today = Date()
        var missing: [String] = []
        for back in 1...(Self.maxFreezes + 1) {
            guard let day = cal.date(byAdding: .day, value: -back, to: today) else { break }
            let k = key(day)
            if activeDays.contains(k) || frozenDays.contains(k) {
                // Found the last active day: freeze the gap if we can afford all of it.
                if !missing.isEmpty, missing.count <= freezes {
                    freezes -= missing.count
                    frozenDays.formUnion(missing)
                    lastEarned = RewardNote(icon: .freeze, text: "Streak freeze used for \(missing.count) missed day\(missing.count == 1 ? "" : "s")")
                    save()
                }
                return
            }
            missing.append(k)
        }
    }

    // MARK: Cloud sync

    struct CloudPart: Codable { var freezes: Int; var skips: Int; var frozenDays: Set<String>; var milestones: Set<Int> }

    func cloudExport() -> CloudPart { CloudPart(freezes: freezes, skips: skips, frozenDays: frozenDays, milestones: streakMilestones) }

    func cloudMerge(_ c: CloudPart) {
        freezes = min(Self.maxFreezes, max(freezes, c.freezes))
        skips = min(Self.maxSkips, max(skips, c.skips))
        frozenDays.formUnion(c.frozenDays)
        streakMilestones.formUnion(c.milestones)
        save()
    }

    func reset() {
        freezes = 1; skips = 2; frozenDays = []; correctSinceSkip = 0; streakMilestones = []; save()
    }
}
