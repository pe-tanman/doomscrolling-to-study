import SwiftUI

/// First-run flow: picture-first, one short headline per step.
/// Welcome → language → level → how it works (animated) → daily goal → free Premium trial.
struct OnboardingView: View {
    @ObservedObject var session: FeedSession
    var onDone: () -> Void

    @AppStorage("targetLanguage") private var targetLanguage = "ja"
    @State private var step = 0
    @State private var level: ScriptLevel = .kanaRomaji
    @State private var goal = 10
    @State private var why: LearningGoal = .culture
    private let steps = 7

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if step > 0 { topBar.transition(.opacity) }
                Group {
                    switch step {
                    case 0: welcome
                    case 1: languagePage
                    case 2: whyPage
                    case 3: levelPage
                    case 4: demoPage
                    case 5: goalPage
                    default: trialPage
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .frame(maxHeight: .infinity)
                cta
            }
        }
        // In .background so the full-bleed picture never widens the layout.
        .background { background }
        .animation(.spring(duration: 0.4), value: step)
        .onAppear {
            level = session.settings.scriptLevel == .kanji ? .kana : session.settings.scriptLevel
            goal = session.settings.dailyGoal
            why = LearningGoal(rawValue: session.settings.goal) ?? .culture
        }
    }

    // MARK: Chrome

    @ViewBuilder private var background: some View {
        if step == 0 || step == steps - 1 {
            GeometryReader { g in
                Image("scene_sky").resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                    .overlay(Color.white.opacity(0.15))
            }
            .ignoresSafeArea()
        } else {
            Brand.sky.ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { step -= 1 } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold)).foregroundStyle(Brand.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            .accessibilityIdentifier("onboarding-back")
            // Progress: one segment per step after the welcome.
            HStack(spacing: 6) {
                ForEach(1..<steps, id: \.self) { i in
                    Capsule().fill(i <= step ? Brand.violet : Brand.line).frame(height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step) of \(steps - 1)")
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
    }

    private var cta: some View {
        Button {
            if step == steps - 1 { finish() } else { step += 1 }
        } label: {
            Text(ctaTitle).frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandPrimary)
        .padding(.horizontal, 24).padding(.bottom, 16).padding(.top, 8)
        .accessibilityIdentifier("onboarding-next")
    }

    private var ctaTitle: String {
        switch step {
        case 0: return "Get started"
        case steps - 1: return "Start watching"
        default: return "Continue"
        }
    }

    private func finish() {
        session.settings.scriptLevel = level
        session.settings.dailyGoal = goal
        session.settings.goal = why.rawValue
        session.settings.dailyLimitMinutes = Self.minutes(for: goal)
        onDone()
    }

    private func headline(_ s: String) -> some View {
        Text(s).font(.largeTitle.weight(.bold)).foregroundStyle(Brand.ink)
            .multilineTextAlignment(.center).padding(.horizontal, 24)
    }

    // MARK: 0 · Welcome

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            MascotImage(mood: .wave, size: 190)
            Text("Upscroll").font(.system(size: 52, weight: .heavy, design: .rounded)).foregroundStyle(Brand.ink)
            HStack(spacing: 14) {
                icon("play.rectangle.fill", Brand.violet)
                Image(systemName: "plus").font(.headline.weight(.bold)).foregroundStyle(Brand.ink2)
                icon("character.bubble.fill", Skill.speaking.color)
                Image(systemName: "equal").font(.headline.weight(.bold)).foregroundStyle(Brand.ink2)
                icon("brain.head.profile.fill", Brand.success)
            }
            .accessibilityElement()
            .accessibilityLabel("Shorts plus new words equals learning")
            Text("Learn a language while you scroll")
                .font(.title3.weight(.semibold)).foregroundStyle(Brand.ink)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.title2).foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 1 · Language

    struct Language: Identifiable {
        let id: String, flag: String, name: String, hello: String, ready: Bool
    }
    static let languages: [Language] = [
        .init(id: "ja", flag: "🇯🇵", name: "Japanese", hello: "こんにちは", ready: true),
        .init(id: "es", flag: "🇪🇸", name: "Spanish", hello: "Hola", ready: false),
        .init(id: "ko", flag: "🇰🇷", name: "Korean", hello: "안녕하세요", ready: false),
        .init(id: "fr", flag: "🇫🇷", name: "French", hello: "Bonjour", ready: false),
        .init(id: "zh", flag: "🇨🇳", name: "Chinese", hello: "你好", ready: false),
        .init(id: "de", flag: "🇩🇪", name: "German", hello: "Hallo", ready: false),
    ]

    private var languagePage: some View {
        ScrollView {
            VStack(spacing: 22) {
                headline("I want to learn…").padding(.top, 20)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Self.languages) { l in languageTile(l) }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func languageTile(_ l: Language) -> some View {
        let selected = l.ready && targetLanguage == l.id
        return Button { if l.ready { targetLanguage = l.id } } label: {
            VStack(spacing: 6) {
                Text(l.flag).font(.system(size: 46))
                Text(l.name).font(.headline).foregroundStyle(Brand.ink)
                Text(l.hello).font(.subheadline.weight(.semibold))
                    .foregroundStyle(l.ready ? Brand.violetDeep : Brand.ink2).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Brand.violet : Brand.line, lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.title3)
                        .foregroundStyle(.white, Brand.violet).padding(10)
                } else if !l.ready {
                    Label("Soon", systemImage: "clock.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Brand.ink2)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Brand.mist, in: Capsule()).padding(8)
                }
            }
            .opacity(l.ready ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!l.ready)
        .accessibilityLabel(l.ready ? l.name : "\(l.name), coming soon")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("lang-\(l.id)")
    }

    // MARK: 2 · Why (steers the personal path)

    private var whyPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                headline("Why Japanese?").padding(.top, 20)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(LearningGoal.allCases) { g in whyTile(g) }
                }
                .padding(.horizontal, 20)
                Label("Your own route", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.headline).foregroundStyle(Brand.violetDeep)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Brand.violetSoft, in: Capsule())
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func whyTile(_ g: LearningGoal) -> some View {
        let selected = why == g
        return Button { why = g } label: {
            VStack(spacing: 8) {
                Text(g.emoji).font(.system(size: 44))
                Text(g.title).font(.headline).foregroundStyle(Brand.ink).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Brand.violet : Brand.line, lineWidth: selected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Brand.violet).padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(g.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("why-\(g.rawValue)")
    }

    // MARK: 3 · Level

    private var levelPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                headline("Your Japanese?").padding(.top, 20)
                VStack(spacing: 12) {
                    // Brand new learners still see kana, with the romaji sound above it (no romaji-only words).
                    levelTile(.kanaRomaji, "🌱", "Brand new")
                    levelTile(.kana, "🌳", "I read kana")
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Each choice previews how "coffee" will look in the captions.
    private func levelTile(_ l: ScriptLevel, _ emoji: String, _ title: String) -> some View {
        let selected = level == l
        return Button { level = l } label: {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 36))
                Text(title).font(.title3.weight(.bold)).foregroundStyle(Brand.ink)
                Spacer(minLength: 8)
                // Caption preview chip
                VStack(spacing: 0) {
                    if l == .kanaRomaji { Text("kōhī").font(.caption.weight(.semibold)).foregroundStyle(Brand.sun) }
                    Text("コーヒー").font(Brand.jp(20, bold: true, relativeTo: .title3))
                        .foregroundStyle(Brand.sun).lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minWidth: 96)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            }
            .padding(16)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Brand.violet : Brand.line, lineWidth: selected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("level-\(l.rawValue)")
    }

    // MARK: 3 · How it works

    private var demoPage: some View {
        VStack(spacing: 20) {
            headline("Just keep scrolling").padding(.top, 20)
            FeedDemo(level: level)
            Spacer(minLength: 0)
        }
    }

    // MARK: 4 · Goal

    static func minutes(for goal: Int) -> Int { goal <= 5 ? 10 : goal <= 10 ? 20 : 30 }

    private var goalPage: some View {
        ScrollView {
            VStack(spacing: 22) {
                headline("Daily goal").padding(.top, 20)
                VStack(spacing: 12) {
                    goalTile(5, "☕️", "Chill")
                    goalTile(10, "🔥", "Regular")
                    goalTile(20, "🚀", "Serious")
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func goalTile(_ n: Int, _ emoji: String, _ title: String) -> some View {
        let selected = goal == n
        return Button { goal = n } label: {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 36))
                Text(title).font(.title3.weight(.bold)).foregroundStyle(Brand.ink)
                Spacer(minLength: 8)
                HStack(spacing: 12) {
                    Label("\(n)", systemImage: "character.bubble.fill")
                    Label("\(Self.minutes(for: n))′", systemImage: "clock.fill")
                }
                .font(.headline).foregroundStyle(Brand.violetDeep)
                .labelStyle(TightLabel())
            }
            .padding(16)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Brand.violet : Brand.line, lineWidth: selected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(n) words, \(Self.minutes(for: n)) minutes a day")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("goal-\(n)")
    }

    // MARK: 5 · Trial

    private var trialPage: some View {
        VStack(spacing: 18) {
            Spacer()
            MascotImage(mood: .gift, size: 170)
            VStack(spacing: 4) {
                Text("\(Plan.trialDays) days").font(.system(size: 48, weight: .heavy, design: .rounded))
                Text("Premium, free").font(.title2.weight(.bold))
            }
            .foregroundStyle(Brand.ink)
            HStack(spacing: 12) {
                perk("waveform", "Voice", Skill.listening.color)
                perk("sparkles", "Smart", Brand.violet)
                perk("photo.fill", "Pictures", Skill.speaking.color)
            }
            Label("No account needed", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline).foregroundStyle(Brand.success)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Brand.successSoft, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func perk(_ symbol: String, _ title: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Brand.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon.font(.subheadline); configuration.title }
    }
}

/// A looping phone mock of the core loop: a Short plays → a caption word turns Japanese → tap → quick card.
struct FeedDemo: View {
    let level: ScriptLevel
    @State private var phase = 0   // 0 caption, 1 tapped (meaning), 2 card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let word = "ねこ"
    /// The romaji sound helper shown above the kana for beginners.
    private var sound: String? { level == .kanaRomaji ? "neko" : nil }

    var body: some View {
        VStack(spacing: 18) {
            phone
            HStack(spacing: 0) {
                stepIcon(0, "play.rectangle.fill")
                connector(1)
                stepIcon(1, "hand.tap.fill")
                connector(2)
                stepIcon(2, "checkmark.circle.fill")
            }
            .padding(.horizontal, 40)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("While you watch, a caption word turns Japanese. Tap it for the meaning, then answer a quick card.")
        .accessibilityIdentifier("feed-demo")
        .task {
            if reduceMotion { phase = 1; return }
            while !Task.isCancelled {
                for p in [0, 1, 2] {
                    withAnimation(.spring(duration: 0.4)) { phase = p }
                    try? await Task.sleep(for: .seconds(p == 2 ? 3 : 2.2))
                }
            }
        }
    }

    private func stepIcon(_ p: Int, _ symbol: String) -> some View {
        Image(systemName: symbol).font(.title3)
            .foregroundStyle(phase >= p ? .white : Brand.ink3)
            .frame(width: 46, height: 46)
            .background(phase >= p ? Brand.violet : Brand.mist, in: Circle())
            .scaleEffect(phase == p ? 1.12 : 1)
    }

    private func connector(_ p: Int) -> some View {
        Capsule().fill(phase >= p ? Brand.violet : Brand.line).frame(height: 4).frame(maxWidth: .infinity)
    }

    private var phone: some View {
        ZStack {
            // The "Short": the illustrated town, slowly panning.
            Image("scene_world").resizable().scaledToFill()
                .frame(width: 220, height: 380)
                .scaleEffect(phase == 2 ? 1.12 : 1.04)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))

            VStack(spacing: 10) {
                Spacer()
                if phase == 1 {
                    HStack(spacing: 6) {
                        VStack(spacing: 0) {
                            if let sound { Text(sound).font(.caption2.weight(.semibold)).foregroundStyle(Brand.sun) }
                            Text(word).font(Brand.jp(17, bold: true)).foregroundStyle(Brand.sun)
                        }
                        Text("= cat").font(.headline).foregroundStyle(.white)
                        Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(Brand.sun)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.6), in: Capsule())
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                if phase < 2 {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("Look, a ").foregroundStyle(.white)
                        VStack(spacing: 0) {
                            if let sound { Text(sound).font(.caption2.weight(.semibold)).foregroundStyle(Brand.sun) }
                            Text(word).font(Brand.jp(17, bold: true)).foregroundStyle(Brand.sun)
                        }
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "hand.point.up.left.fill").font(.title2).foregroundStyle(.white)
                                    .offset(x: 18, y: 22).opacity(phase == 0 ? 1 : 0)
                            }
                        Text("!").foregroundStyle(.white)
                    }
                    .font(.headline)
                    .padding(.bottom, 34)
                } else {
                    card.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: 220, height: 380)
        }
        .frame(width: 220, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Brand.ink, lineWidth: 6))
        .overlay(alignment: .top) { Capsule().fill(Brand.ink).frame(width: 70, height: 18).padding(.top, 10) }
    }

    private var card: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                if let sound { Text(sound).font(.caption.weight(.semibold)).foregroundStyle(Brand.sun) }
                Text(word).font(Brand.jp(26, bold: true)).foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                answer("🐶", false)
                answer("🐱", true)
                answer("🐟", false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(10)
    }

    private func answer(_ emoji: String, _ right: Bool) -> some View {
        Text(emoji).font(.system(size: 28))
            .frame(width: 52, height: 48)
            .background(right ? Brand.OnDark.right.opacity(0.9) : .white.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
