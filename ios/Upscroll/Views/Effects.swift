import SwiftUI

/// Answer effects shared by every question in the app: a sparkle burst for right, a short shake for wrong.
/// `SoundFX.answered` fires them together with the sound and haptic; views opt in with `.answerEffects()`.
@MainActor
final class EffectCenter: ObservableObject {
    static let shared = EffectCenter()
    @Published private(set) var burst = 0
    @Published private(set) var shake = 0
    func right() { burst += 1 }
    func wrong() { shake += 1 }
}

extension SoundFX {
    /// Sound + haptic + visual effect for an answer, everywhere in the app.
    static func answer(correct: Bool) {
        answered(correct: correct)
        correct ? EffectCenter.shared.right() : EffectCenter.shared.wrong()
    }
}

/// A ring of sparkles that flies out and fades each time `trigger` changes.
struct SparkleBurst: View {
    let trigger: Int
    var count = 10
    var distance: CGFloat = 90
    var size: CGFloat = 16
    @State private var fired = false
    @State private var seen = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let palette: [Color] = [Brand.sun, Brand.sakura, Brand.OnDark.mint, Brand.OnDark.violet, Brand.OnDark.cyan]
    private static let symbols = ["sparkle", "star.fill", "circle.fill"]

    var body: some View {
        ZStack {
            if !reduceMotion && seen > 0 {
                ForEach(0..<count, id: \.self) { i in
                    let angle = Double(i) / Double(count) * 2 * .pi + Double(seen) * 0.4
                    let d = fired ? distance * (i % 2 == 0 ? 1 : 0.7) : 6
                    Image(systemName: Self.symbols[i % Self.symbols.count])
                        .font(.system(size: i % 3 == 0 ? size : size * 0.65, weight: .bold))
                        .foregroundStyle(Self.palette[i % Self.palette.count])
                        .offset(x: cos(angle) * d, y: sin(angle) * d)
                        .scaleEffect(fired ? 1.2 : 0.3)
                        .opacity(fired ? 0 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, t in
            seen = t
            fired = false
            withAnimation(.easeOut(duration: 0.75)) { fired = true }
        }
    }
}

/// Opt in: this view sparkles on a right answer and shakes on a wrong one.
struct AnswerEffects: ViewModifier {
    @ObservedObject private var center = EffectCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(0), trigger: center.shake) { view, x in
                view.offset(x: reduceMotion ? 0 : x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-9, duration: 0.06)
                    LinearKeyframe(8, duration: 0.08)
                    LinearKeyframe(-5, duration: 0.07)
                    LinearKeyframe(3, duration: 0.06)
                    SpringKeyframe(0, duration: 0.15)
                }
            }
            .overlay { SparkleBurst(trigger: center.burst, count: 12, distance: 110) }
    }
}

extension View {
    func answerEffects() -> some View { modifier(AnswerEffects()) }
}
