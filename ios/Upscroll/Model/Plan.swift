import Foundation
import Security

/// Plans. No account is needed for any of them.
/// - Premium trial: starts the first time the app opens and lasts `trialDays` days.
/// - Free: what the app becomes after the trial. Everything still works; the three features that cost
///   server money per use get a smaller daily allowance, and past it the app quietly uses the on-phone
///   version (iPhone voice, on-device word picks, no picture questions) instead of blocking anything.
/// - Premium: same allowance as the trial (set by `unlockPremium`, e.g. after a purchase).
/// Counts reset at midnight.
enum Plan {
    enum Tier { case trial, free, premium }

    enum Feature: String, CaseIterable {
        case naturalVoice, smartPicks, pictureQuestions

        /// Per-day allowance on the current plan.
        var dailyLimit: Int { Plan.isPremium ? premiumLimit : freeLimit }
        var premiumLimit: Int {
            switch self {
            case .naturalVoice: return 600       // new spoken words/lines per day (replays are cached and free)
            case .smartPicks: return 400         // Shorts checked per day
            case .pictureQuestions: return 200   // video frames analysed per day
            }
        }
        var freeLimit: Int {
            switch self {
            case .naturalVoice: return 40
            case .smartPicks: return 40
            case .pictureQuestions: return 0
            }
        }
        var title: String {
            switch self {
            case .naturalVoice: return "Natural voice"
            case .smartPicks: return "Smarter word choice"
            case .pictureQuestions: return "Picture questions"
            }
        }
        var symbol: String {
            switch self {
            case .naturalVoice: return "waveform"
            case .smartPicks: return "sparkles"
            case .pictureQuestions: return "photo"
            }
        }
        /// What Free gets instead, in a few words.
        var freeNote: String {
            switch self {
            case .naturalVoice: return "\(freeLimit) a day, then the iPhone voice"
            case .smartPicks: return "\(freeLimit) Shorts a day, then on-phone picks"
            case .pictureQuestions: return "Premium only"
            }
        }
    }

    static let trialDays = 30

    // MARK: Tier

    static var tier: Tier {
        if UserDefaults.standard.bool(forKey: premiumKey) { return .premium }
        return trialDaysLeft > 0 ? .trial : .free
    }
    static var isPremium: Bool { tier != .free }

    static var name: String {
        switch tier {
        case .trial: return "Premium trial"
        case .free: return "Free"
        case .premium: return "Premium"
        }
    }

    /// When the trial started: the first launch on this phone. Kept in the Keychain too, so deleting and
    /// reinstalling the app doesn't restart it.
    static var trialStart: Date {
        if let d = UserDefaults.standard.object(forKey: trialKey) as? Date { return d }
        let d = Keychain.date(trialKey) ?? Date()
        UserDefaults.standard.set(d, forKey: trialKey)
        Keychain.setDate(d, trialKey)
        return d
    }
    static var trialEnd: Date { Calendar.current.date(byAdding: .day, value: trialDays, to: trialStart) ?? trialStart }
    /// Whole days left, rounded up (0 once it has ended).
    static var trialDaysLeft: Int {
        let secs = trialEnd.timeIntervalSinceNow
        return secs <= 0 ? 0 : Int((secs / 86400).rounded(.up))
    }

    /// Call once at launch so the trial clock starts on first open, not on first use of a feature.
    static func startTrialIfNeeded() { _ = trialStart }

    /// Paid Premium (no store purchase is wired up yet; this is the hook for it).
    static func unlockPremium(_ on: Bool = true) { UserDefaults.standard.set(on, forKey: premiumKey) }

    #if DEBUG
    /// Debug: move the trial start so the trial looks `daysAgo` days old.
    static func debugSetTrialAge(days daysAgo: Int) {
        let d = Date().addingTimeInterval(-Double(daysAgo) * 86400)
        UserDefaults.standard.set(d, forKey: trialKey)
        Keychain.setDate(d, trialKey)
    }
    #endif

    private static let trialKey = "plan.trialStart"
    private static let premiumKey = "plan.premium"

    // MARK: Daily allowance

    private static func key(_ f: Feature) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "plan.\(f.rawValue).\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func used(_ f: Feature) -> Int { UserDefaults.standard.integer(forKey: key(f)) }

    /// Room left today (callers can skip work, like grabbing a video frame, when there's none).
    static func allows(_ f: Feature) -> Bool { used(f) < f.dailyLimit }

    /// Counts one use; false once today's allowance is spent (callers fall back to the on-phone path).
    static func consume(_ f: Feature) -> Bool {
        let k = key(f), n = UserDefaults.standard.integer(forKey: k)
        guard n < f.dailyLimit else { return false }
        UserDefaults.standard.set(n + 1, forKey: k)
        return true
    }

    struct LimitReached: LocalizedError {
        let feature: Feature
        var errorDescription: String? { "\(feature.title): today's \(Plan.name) allowance is used up, using the on-phone version" }
    }
}

/// Tiny Keychain store for values that should survive an app reinstall.
private enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.upscroll.app.plan",
         kSecAttrAccount as String: key]
    }

    static func date(_ key: String) -> Date? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              let t = Double(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func setDate(_ d: Date, _ key: String) {
        let data = Data(String(d.timeIntervalSince1970).utf8)
        SecItemDelete(query(key) as CFDictionary)
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
