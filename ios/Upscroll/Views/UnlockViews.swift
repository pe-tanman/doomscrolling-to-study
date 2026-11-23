import SwiftUI

/// One goal row: what's next, how far along, and roughly how long it takes.
struct UnlockGoalRow: View {
    let goal: UnlockGoal
    var label = "Next"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: goal.symbol).font(.subheadline.weight(.bold)).foregroundStyle(Brand.violet)
                    .frame(width: 28, height: 28).background(Brand.violetSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(label): \(goal.title)").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                    Text(goal.detail).font(.caption).foregroundStyle(Brand.ink2).lineLimit(2)
                }
                Spacer(minLength: 4)
                Text("\(Int((goal.progress * 100).rounded()))%").font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Brand.violetDeep)
            }
            ProgressBar(value: goal.progress, height: 8)
            Label(goal.estimate, systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(Brand.ink2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(goal.title). \(goal.detail). \(Int((goal.progress * 100).rounded())) percent. \(goal.estimate)")
    }
}

/// Home: just the essentials of what unlocks next (and kana progress in one line). Tap → the full card in Progress.
struct NextUnlockCard: View {
    let wordsLearned: Int
    let dailyGoal: Int
    var onOpen: () -> Void = {}
    @ObservedObject private var kana = KanaProgress.shared
    @ObservedObject private var grammar = GrammarBook.shared

    var body: some View {
        let stage = LadderStage.current(wordsLearned: wordsLearned, grammar: grammar)
        let next = LadderStage.allCases.first { $0 > stage }
        let goal = Unlocks.ladderGoal(wordsLearned: wordsLearned, grammar: grammar, dailyGoal: dailyGoal)
        if next != nil || !kana.isComplete {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    if let next, let goal {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("NEXT UNLOCK", systemImage: "lock.fill").font(.caption.weight(.heavy)).foregroundStyle(Brand.OnIndigo.gold)
                                Text(next.title).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                                Text(goal.detail).font(.subheadline).foregroundStyle(Brand.OnIndigo.muted).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            ProgressRing(value: goal.progress)
                        }
                        Label(goal.estimate, systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(Brand.OnIndigo.muted)
                    }
                    if !kana.isComplete {
                        HStack(spacing: 8) {
                            Text("あ").font(Brand.jp(14, bold: true)).foregroundStyle(Brand.violetDeep)
                                .frame(width: 24, height: 24).background(.white, in: Circle())
                            Text("Kana sounds").font(.caption.weight(.bold)).foregroundStyle(.white)
                            ProgressBar(value: Double(kana.count) / Double(kana.total), color: Brand.sun, height: 6, track: .white.opacity(0.25))
                            Text("\(kana.count)/\(kana.total)").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Kana sounds: \(kana.count) of \(kana.total)")
                        .accessibilityIdentifier("kana-track")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.heroGradient,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7)).padding(12)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens Progress with what's coming and your kana")
            .accessibilityIdentifier("next-unlock")
        }
    }
}

/// Progress: the full picture of what's next: what the practice is, a locked preview of the actual question,
/// how far along, how long it takes, kana practice tile by tile, and the whole path.
struct UnlockDetailCard: View {
    let wordsLearned: Int
    let dailyGoal: Int
    @ObservedObject private var kana = KanaProgress.shared
    @ObservedObject private var grammar = GrammarBook.shared

    private var stage: LadderStage { LadderStage.current(wordsLearned: wordsLearned, grammar: grammar) }
    private var next: LadderStage? { LadderStage.allCases.first { $0 > stage } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let next, let goal = Unlocks.ladderGoal(wordsLearned: wordsLearned, grammar: grammar, dailyGoal: dailyGoal) {
                teaser(next, goal)
            } else {
                Label("Every practice type is unlocked", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.white)
            }
            kanaTrack
            path
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.heroGradient,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unlock-detail")
    }

    // MARK: Teaser for the next practice type

    @ViewBuilder private func teaser(_ next: LadderStage, _ goal: UnlockGoal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("NEXT UNLOCK", systemImage: "lock.fill")
                        .font(.caption.weight(.heavy)).foregroundStyle(Brand.OnIndigo.gold)
                    Text(next.title).font(.system(.title, design: .rounded).weight(.heavy)).foregroundStyle(.white)
                    Text(Self.pitch(next)).font(.subheadline).foregroundStyle(Brand.OnIndigo.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ProgressRing(value: goal.progress)
            }
            preview(next)
            VStack(alignment: .leading, spacing: 6) {
                ProgressBar(value: goal.progress, color: Brand.sun, height: 10, track: .white.opacity(0.25))
                Text(goal.detail).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Label(goal.estimate, systemImage: "clock").font(.caption.weight(.semibold)).foregroundStyle(Brand.OnIndigo.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next unlock: \(next.title). \(Self.pitch(next)). \(Int((goal.progress * 100).rounded())) percent. \(goal.detail). \(goal.estimate)")
    }

    /// What the new practice lets you do, in one line.
    static func pitch(_ s: LadderStage) -> String {
        switch s {
        case .words: return "Japanese words swapped into your Shorts."
        case .chunks: return "Fill the gap in real lines from your Shorts: the little words that glue Japanese together."
        case .patterns: return "Endings that change the meaning: want to, doing now, please do."
        case .sentences: return "Whole lines from your Shorts: read them, build them, say them."
        }
    }

    /// A locked sample of the actual question, so it's clear what's coming.
    @ViewBuilder private func preview(_ s: LadderStage) -> some View {
        let (en, before, after, options): (String, String, String, [String]) = switch s {
        case .chunks: ("I want to eat ramen", "ラーメン", "食べたい", ["が", "を", "に"])
        case .patterns: ("I'm eating now", "今 食べ", "", ["てる", "た", "たい"])
        case .sentences: ("Wait a second!", "", "", ["待って", "ちょっと"])
        case .words: ("I like big boys", "", "", ["おおきい"])
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("\u{201C}\(en)\u{201D}").font(.footnote.weight(.semibold)).foregroundStyle(Brand.ink2)
            if s == .sentences {
                HStack(spacing: 6) {
                    ForEach(["＿＿＿", "＿＿＿"], id: \.self) { _ in slot }
                }
            } else {
                HStack(spacing: 4) {
                    Text(before).font(Brand.jp(20, bold: true)).foregroundStyle(Brand.ink)
                    slot
                    Text(after).font(Brand.jp(20, bold: true)).foregroundStyle(Brand.ink)
                }
            }
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { o in
                    Text(o).font(Brand.jp(16, bold: true)).foregroundStyle(Brand.violetDeep)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Brand.violetSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer(minLength: 0)
                Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(Brand.ink3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    private var slot: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Brand.violet, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .frame(width: 44, height: 30)
            .overlay(Text("?").font(.headline).foregroundStyle(Brand.violet))
    }

    // MARK: The whole path

    private var path: some View {
        let steps: [(String, String, Bool, Bool)] = [   // title, symbol, done (or open), current
            // Kana practice is never locked: it's open (in progress) until complete.
            ("Sounds", "character.ja", true, !kana.isComplete),
            ("Words", "textformat.abc", stage >= .words, stage == .words),
            ("Chunks", "square.stack.3d.up.fill", stage >= .chunks, stage == .chunks),
            ("Patterns", "arrow.triangle.branch", stage >= .patterns, stage == .patterns),
            ("Sentences", "text.bubble.fill", stage >= .sentences, stage == .sentences),
        ]
        return HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, st in
                VStack(spacing: 4) {
                    Image(systemName: st.2 ? (st.3 ? st.1 : "checkmark") : "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(st.2 ? Brand.violetDeep : .white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(st.2 ? (st.3 ? Brand.sun : .white) : .white.opacity(0.18), in: Circle())
                    Text(st.0).font(.caption2.weight(st.3 ? .bold : .medium)).foregroundStyle(.white).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                if i < steps.count - 1 {
                    Capsule().fill(.white.opacity(steps[i + 1].2 ? 0.9 : 0.25)).frame(height: 2).frame(maxWidth: 12)
                        .padding(.bottom, 16)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Path: " + steps.map { "\($0.0) \($0.2 ? ($0.3 ? "in progress" : "done") : "locked")" }.joined(separator: ", "))
    }

    // MARK: Kana practice, visible

    @ViewBuilder private var kanaTrack: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Kana sounds", systemImage: "character.ja").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Spacer()
                Text(kana.isComplete ? "Complete" : "\(kana.count)/\(kana.total)")
                    .font(.subheadline.weight(.bold)).monospacedDigit().foregroundStyle(.white)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 11), spacing: 4) {
                ForEach(KanaProgress.drillSet, id: \.self) { k in
                    let got = kana.known.contains(k)
                    Text(k).font(Brand.jp(12, bold: true))
                        .foregroundStyle(got ? Brand.violetDeep : Brand.OnIndigo.muted)
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(got ? Color.white : .white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .accessibilityHidden(true)
            if let g = Unlocks.kanaGoal(kana) {
                Label("\(g.estimate) · they come on Shorts without talking", systemImage: "clock")
                    .font(.caption.weight(.semibold)).foregroundStyle(Brand.OnIndigo.muted)
            }
        }
        .padding(12)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kana.isComplete ? "Kana sounds complete" : "Kana sounds: \(kana.count) of \(kana.total). \(Unlocks.kanaGoal(kana)?.estimate ?? "")")
        .accessibilityIdentifier("kana-track")
    }
}

/// Circular progress with the percentage inside.
struct ProgressRing: View {
    let value: Double
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 6)
            Circle().trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(Brand.sun, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))%").font(.caption.weight(.heavy)).monospacedDigit().foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

/// Over the feed, right after the answer that unlocked something: a short burst and the news.
struct UnlockCelebration: View {
    let event: UnlockEvent
    var onDone: () -> Void
    @State private var shown = false
    @State private var burst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pieces: [(symbol: String, color: Color)] = [
        ("sparkle", Brand.sun), ("star.fill", Brand.sakura), ("sparkle", Brand.OnDark.violet), ("circle.fill", Brand.sun),
        ("star.fill", Brand.OnDark.mint), ("sparkle", Brand.sakura), ("circle.fill", Brand.OnDark.cyan), ("star.fill", Brand.sun),
        ("sparkle", Brand.OnDark.mint), ("circle.fill", Brand.sakura), ("star.fill", Brand.OnDark.violet), ("sparkle", Brand.OnDark.cyan),
    ]

    var body: some View {
        ZStack {
            // Burst: pieces fly out from behind the card and fade.
            if !reduceMotion {
                ForEach(Array(Self.pieces.enumerated()), id: \.offset) { i, p in
                    let angle = Double(i) / Double(Self.pieces.count) * 2 * .pi
                    let dist: CGFloat = burst ? CGFloat(140 + (i % 3) * 40) : 10
                    Image(systemName: p.symbol)
                        .font(.system(size: i % 2 == 0 ? 22 : 14, weight: .bold))
                        .foregroundStyle(p.color)
                        .offset(x: cos(angle) * dist, y: sin(angle) * dist)
                        .opacity(burst ? 0 : 1)
                        .scaleEffect(burst ? 1.3 : 0.4)
                        .accessibilityHidden(true)
                }
            }
            VStack(spacing: 10) {
                Image(systemName: event.symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(Brand.violetDeep)
                    .frame(width: 64, height: 64).background(Brand.sunSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(event.title).font(.title3.weight(.bold)).foregroundStyle(Brand.ink).multilineTextAlignment(.center)
                Text(event.message).font(.subheadline).foregroundStyle(Brand.ink2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: 300)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Brand.sun, lineWidth: 3))
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .environment(\.colorScheme, .light)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to close")
        .accessibilityIdentifier("unlock-celebration")
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            SoundFX.play(.unlock)
            withAnimation(.spring(duration: 0.45, bounce: 0.4)) { shown = true }
            withAnimation(.easeOut(duration: 1.1)) { burst = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(4))
            onDone()
        }
    }
}

/// Over the feed, near the top: a short milestone message ("You learned 10 new words today!", "50% to unlock
/// Chunks!"). Never pauses the Short or blocks taps; leaves after 3 s.
struct NudgeBanner: View {
    let nudge: ProgressNudge
    var onDone: () -> Void
    @State private var shown = false
    @State private var filled = false
    @State private var sparkle = 0
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Small and at the very top edge (over the YouTube bar), so it never covers the video.
        // One slim line (icon · text · tiny bar) so it fits in the black bar between the Dynamic Island and the video.
        HStack(spacing: 7) {
            Image(systemName: nudge.symbol).font(.caption2.weight(.bold)).foregroundStyle(Brand.violetDeep)
                .frame(width: 20, height: 20).background(Brand.sun, in: Circle())
                .scaleEffect(shown || reduceMotion ? 1 : 0.4)
                .overlay { SparkleBurst(trigger: sparkle, count: 8, distance: 26, size: 8) }
                .accessibilityHidden(true)
            Text(nudge.text).font(.caption.weight(.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            if let p = nudge.progress {
                ProgressBar(value: filled ? p : max(0, p - 0.15), color: Brand.sun, height: 4, track: .white.opacity(0.25))
                    .frame(width: 44)
            }
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(Color.black.opacity(0.78), in: Capsule())
        .overlay {
            // One light sweep across the pill when it arrives.
            if !reduceMotion {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 50)
                        .offset(x: shimmer ? g.size.width + 50 : -60)
                }
                .clipShape(Capsule())
                .allowsHitTesting(false)
            }
        }
        .overlay(Capsule().strokeBorder(Brand.sun.opacity(0.55), lineWidth: 1))
        .offset(y: shown || reduceMotion ? 0 : -24)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("progress-nudge")
        .onAppear {
            SoundFX.play(.milestone)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: nudge.text)
            withAnimation(.spring(duration: 0.4, bounce: 0.35)) { shown = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.3)) { filled = true }   // the bar grows to where you are
            withAnimation(.easeInOut(duration: 0.8).delay(0.25)) { shimmer = true }
            sparkle += 1
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeIn(duration: 0.25)) { shown = false }
            try? await Task.sleep(for: .milliseconds(260))
            onDone()
        }
    }
}
