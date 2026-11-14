import SwiftUI

/// The app's own reward icons, used everywhere a reward is shown (inventory, toasts, gift offers, good stop),
/// never emoji: one look for each reward across the app.
enum RewardIcon: String, Hashable {
    case freeze, skip, gift

    var symbol: String {
        switch self {
        case .freeze: return "snowflake"
        case .skip: return "forward.end.fill"
        case .gift: return "gift.fill"
        }
    }

    var color: Color {
        switch self {
        case .freeze: return Brand.ice
        case .skip: return Brand.violet
        case .gift: return Brand.sunDeep
        }
    }

    var name: String {
        switch self {
        case .freeze: return "streak freeze"
        case .skip: return "skip ticket"
        case .gift: return "gift"
        }
    }

    /// The icon as text, so it can sit inside a sentence ("+1 [icon] streak freeze").
    /// tinted false: inherit the surrounding text color (e.g. white on a filled button).
    func text(tinted: Bool = true) -> Text {
        let t = Text(Image(systemName: symbol))
        return tinted ? t.foregroundStyle(color) : t
    }
}

/// A reward line built from icons and words: Text pieces joined in order.
enum RewardText {
    /// "+1 [freeze icon] streak freeze and +2 [skip icon] skip tickets".
    static func signInGift(tinted: Bool = true) -> Text {
        Text("+\(Rewards.signInFreezes) ") + RewardIcon.freeze.text(tinted: tinted) + Text(" streak freeze and +\(Rewards.signInSkips) ")
            + RewardIcon.skip.text(tinted: tinted) + Text(" skip tickets")
    }

    /// Short form for tight rows: gift icon, "Gift: +1", freeze icon, "+2", skip icon.
    static func signInGiftShort() -> Text {
        RewardIcon.gift.text() + Text(" Gift: +\(Rewards.signInFreezes) ") + RewardIcon.freeze.text()
            + Text(" +\(Rewards.signInSkips) ") + RewardIcon.skip.text()
    }
}

/// What the "you got…" toast shows: the reward's icon and a plain sentence.
struct RewardNote: Hashable {
    let icon: RewardIcon
    let text: String
}
