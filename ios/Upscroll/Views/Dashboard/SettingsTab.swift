import SwiftUI

/// Settings, grouped by what the learner is deciding:
/// plan → account → what to learn → how scrolling feels → sound → screen time → YouTube → help.
/// Fine-grained scrolling controls live one level down, under "Customize".
struct SettingsTab: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @State private var confirmReset = false
    @State private var confirmSignOut = false
    @State private var showFeedSheet = false
    @State private var showSignIn = false
    /// Debug tools stay hidden unless unlocked by a long-press on "Reset all progress" (developers only).
    @AppStorage("showDebugTools") private var showDebugTools = false
    @AppStorage(Speech.naturalVoiceKey) private var naturalVoice = true
    @Environment(\.dismiss) private var dismiss

    private var sample: VocabEntry? { session.vocab.byId["tired"] }

    var body: some View {
        Form {
            PlanSection()

            AccountSection { showSignIn = true }

            Section("Learning") {
                // Steers the personal route (Jev rebuilds it when this changes).
                Picker(selection: $session.settings.goal) {
                    ForEach(LearningGoal.allCases) { Text("\($0.emoji) \($0.title)").tag($0.rawValue) }
                } label: { Label("Goal", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill") }
                .accessibilityIdentifier("goal-picker")
                Picker(selection: $session.settings.jlptLevel) {
                    ForEach(JLPT.levels, id: \.self) { lv in
                        Text("N\(lv) · \(JLPT.title(lv))").tag(lv)
                    }
                } label: { Label("Level", systemImage: "chart.bar.fill") }
                Picker(selection: $session.settings.scriptLevel) {
                    ForEach(ScriptLevel.allCases) { Text($0.label).tag($0) }
                } label: { Label("Script", systemImage: "character.ja") }
                if let e = sample { scriptPreview(e) }
                Stepper(value: $session.settings.dailyGoal, in: 5...50, step: 5) {
                    Label("\(session.settings.dailyGoal) words a day", systemImage: "target")
                }
            }

            Section("While scrolling") {
                Picker(selection: Binding(
                    get: { Self.preset(session.settings) },
                    set: { Self.apply(preset: $0, to: &session.settings) })) {
                    Label("Light", systemImage: "leaf").tag(0)
                    Label("Normal", systemImage: "circle.lefthalf.filled").tag(1)
                    Label("Study", systemImage: "flame").tag(2)
                    if Self.preset(session.settings) == 3 { Label("Custom", systemImage: "slider.horizontal.3").tag(3) }
                } label: { Label("Interruptions", systemImage: "pause.circle.fill") }
                .accessibilityIdentifier("interruption-preset")
                NavigationLink { ScrollingOptionsView(session: session) } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("customize-scrolling")
            }

            Section("Sound") {
                Toggle(isOn: $session.settings.autoSpeak) { Label("Auto-play words", systemImage: "speaker.wave.2.fill") }
                Toggle(isOn: $naturalVoice) { Label("Natural voice", systemImage: "waveform") }
            }

            Section("Screen time") {
                Stepper(value: $session.settings.dailyLimitMinutes, in: 0...120, step: 5) {
                    Label(session.settings.dailyLimitMinutes == 0 ? "No limit" : "\(session.settings.dailyLimitMinutes) min a day",
                          systemImage: "hourglass")
                }
            }

            Section("YouTube") {
                if session.signedIn == true {
                    LabeledContent {
                        Button("Sign out", role: .destructive) { confirmSignOut = true }
                    } label: { Label("Signed in", systemImage: "checkmark.circle.fill") }
                } else {
                    Button { go(WebController.signInURL) } label: { Label("Sign in to YouTube", systemImage: "person.badge.key.fill") }
                }
                Button { showFeedSheet = true } label: { Label("More Japanese Shorts", systemImage: "globe.asia.australia.fill") }
            }

            Section("Help") {
                NavigationLink { HowItWorksView() } label: {
                    Label("How Upscroll works", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("how-it-works")
                NavigationLink { CreditsView() } label: { Label("Credits", systemImage: "text.book.closed") }
                Link(destination: URL(string: "https://upscroll-lesson.vercel.app/api/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                Link(destination: URL(string: "https://upscroll-lesson.vercel.app/api/support")!) {
                    Label("Support", systemImage: "envelope.fill")
                }
            }

            #if DEBUG
            if showDebugTools {
            Section("Debug") {
                Toggle("Show Japanese captions while playing", isOn: $session.settings.showJapaneseLineWhilePlaying)
                NavigationLink { QuestionLab(session: session, wordBook: wordBook, journey: session.journey) } label: {
                    Label("Question Lab", systemImage: "testtube.2")
                }
                .accessibilityIdentifier("open-lab")
                NavigationLink("Diagnostics") { DebugTab(session: session) }
                Button("Trial: make it day 1") { Plan.debugSetTrialAge(days: 0) }
                Button("Trial: end it (Free plan)") { Plan.debugSetTrialAge(days: Plan.trialDays + 1) }
            }
            }
            #endif

            Section {
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset all progress", systemImage: "arrow.counterclockwise") }
                    // Developers: long-press to show the debug tools.
                    .simultaneousGesture(LongPressGesture(minimumDuration: 1.5).onEnded { _ in showDebugTools.toggle() })
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.sky)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { session.refreshSignedIn() }
        .sheet(isPresented: $showFeedSheet) { JapaneseFeedSheet(session: session, journey: session.journey) }
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .confirmationDialog("Sign out of YouTube?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { session.web.signOut { session.refreshSignedIn() } }
        } message: {
            Text("This clears YouTube and Google cookies in the app. Your words and progress stay.")
        }
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { wordBook.reset(); session.journey.reset(); Rewards.shared.reset() }
        } message: {
            Text("Your word collection, review schedule, streak, journey and rewards will be deleted.")
        }
    }

    private func scriptPreview(_ e: VocabEntry) -> some View {
        let shown = session.settings.scriptLevel.display(e)
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            Image(systemName: "eye.fill").foregroundStyle(Brand.ink2).accessibilityLabel("Preview")
            Spacer()
            Text("I'm so ")
            VStack(spacing: 0) {
                if let sub = shown.sub { Text(sub).font(.caption).foregroundStyle(Brand.violetDeep) }
                Text(shown.main).font(.headline.weight(.heavy)).foregroundStyle(Brand.violetDeep)
            }
            Text(" today")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("preview-meaning")
    }

    /// 0 light, 1 normal, 2 study, 3 custom.
    static func preset(_ s: LearnerSettings) -> Int {
        switch (s.wordsPerVideo, s.cardEvery, s.originals) {
        case (1, 1, false): return 0
        case (2, 1, true): return 1
        case (3, 1, true): return 2
        default: return 3
        }
    }

    static func apply(preset p: Int, to s: inout LearnerSettings) {
        switch p {
        // Every preset asks at least one question on every Short; they differ in how many.
        case 0: s.wordsPerVideo = 1; s.cardEvery = 1; s.originals = false
        case 1: s.wordsPerVideo = 2; s.cardEvery = 1; s.originals = true
        case 2: s.wordsPerVideo = 3; s.cardEvery = 1; s.originals = true
        default: break
        }
    }

    private func go(_ url: URL) {
        session.web.open(url)
        dismiss()
    }
}

/// Plan status: days left in the trial, or the plan's name.
struct PlanSection: View {
    var body: some View {
        Section {
            NavigationLink { PlanDetailView() } label: {
                HStack(spacing: 12) {
                    Image(systemName: Plan.isPremium ? "crown.fill" : "gift.fill")
                        .font(.title2).foregroundStyle(Plan.isPremium ? Brand.sunDeep : Brand.ink2)
                        .frame(width: 30)
                    Text(Plan.name).font(.headline)
                    Spacer()
                    if Plan.tier == .trial {
                        Label("\(Plan.trialDaysLeft)", systemImage: "calendar")
                            .font(.headline.monospacedDigit()).foregroundStyle(Brand.violetDeep)
                            .accessibilityLabel("\(Plan.trialDaysLeft) days left")
                    }
                }
            }
            .accessibilityIdentifier("plan-status")
        }
    }
}

struct PlanDetailView: View {
    var body: some View {
        List {
            if Plan.tier == .trial {
                LabeledContent { Text(Plan.trialEnd.formatted(date: .abbreviated, time: .omitted)) } label: {
                    Label("Trial ends", systemImage: "calendar")
                }
            }
            Section("Premium") {
                ForEach(Plan.Feature.allCases, id: \.self) { f in
                    LabeledContent {
                        if Plan.isPremium { Text("\(min(Plan.used(f), f.dailyLimit))/\(f.dailyLimit)").monospacedDigit() }
                        else if f.freeLimit > 0 { Text("\(f.freeLimit)/day").monospacedDigit() }
                        else { Image(systemName: "lock.fill") }
                    } label: { Label(f.title, systemImage: f.symbol) }
                }
            }
            Section("Always free") {
                Label("Words in Shorts", systemImage: "captions.bubble")
                Label("Every practice type", systemImage: "rectangle.stack")
                Label("Journey map & quests", systemImage: "map")
                Label("Progress & rewards", systemImage: "chart.bar")
                Label("Cloud save", systemImage: "icloud")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.sky)
        .navigationTitle(Plan.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The detailed scrolling controls behind "Customize". Changing any of them makes the preset "Custom".
struct ScrollingOptionsView: View {
    @ObservedObject var session: FeedSession
    @AppStorage(SoundFX.enabledKey) private var soundEffects = true

    var body: some View {
        Form {
            Section {
                Stepper(value: $session.settings.wordsPerVideo, in: 1...3) {
                    Label("\(session.settings.wordsPerVideo) word\(session.settings.wordsPerVideo == 1 ? "" : "s") per Short", systemImage: "character.bubble")
                }
                Picker(selection: $session.settings.cardEvery) {
                    Text("Every Short").tag(1)
                    Text("Only when I ask").tag(0)
                } label: { Label("Cards", systemImage: "rectangle.on.rectangle") }
                .accessibilityIdentifier("card-pace")
            }
            Section {
                Toggle(isOn: $session.settings.originals) { Label("Originals", systemImage: "sparkles.tv") }
                Toggle(isOn: $soundEffects) { Label("Sound effects", systemImage: "speaker.wave.2.fill") }
                    .accessibilityIdentifier("sound-effects")
                Toggle(isOn: $session.settings.speakingInFeed) { Label("Speaking", systemImage: "mic.fill") }
                Toggle(isOn: $session.settings.showJapaneseSentence) { Label("Japanese sentence", systemImage: "text.bubble") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.sky)
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Text("JLPT N5–N1 word lists by Jonathan Waller (tanos.co.uk, CC BY), via open-anki-jlpt-decks (MIT).")
            Text("Japanese captions are YouTube's own machine translations of each Short.")
        }
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Beginner guide: what each part of the feed does. Reachable any time from Settings.
struct HowItWorksView: View {
    var body: some View {
        List {
            Section { CaptionDemo().listRowBackground(Color.black) }
            row("play.rectangle.fill", "Watch Shorts", "1–2 words in the captions turn Japanese")
            row("hand.tap.fill", "Tap a yellow word", "Meaning + sound")
            row("rectangle.on.rectangle", "Word cards", "The video pauses for a quick card")
            row("character.ja", "The あ button", "Your words, reviews and progress")
            row("hourglass", "Daily limit", "Stop at the recap: get a gift")
            row("chart.bar.fill", "Levels", "N5 = first words")
            row("globe.asia.australia.fill", "More Japanese", "Settings → YouTube")
        }
        .navigationTitle("How Upscroll works")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Brand.violet).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(body).font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A looping 6-second example of the core idea: a caption with one yellow Japanese word, a tap, its meaning.
struct CaptionDemo: View {
    @State private var tapped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            if tapped {
                HStack(spacing: 8) {
                    Text("つかれた").font(.headline.weight(.heavy)).foregroundStyle(.yellow)
                    Text("tsukareta").font(.subheadline).foregroundStyle(.white)
                    Text("= tired").font(.headline).foregroundStyle(.white)
                    Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(.yellow)
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("I'm so ").font(.headline).foregroundStyle(.white)
                VStack(spacing: 0) {
                    Text("tsukareta").font(.caption).foregroundStyle(.yellow)
                    Text("つかれた").font(.headline.weight(.heavy)).foregroundStyle(.yellow)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "hand.tap.fill").font(.title3).foregroundStyle(.white)
                        .offset(x: 14, y: 18).opacity(tapped ? 0 : 0.9)
                }
                Text(" today").font(.headline).foregroundStyle(.white)
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            Image(systemName: tapped ? "speaker.wave.2.fill" : "hand.tap.fill")
                .font(.headline).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example caption: I'm so つかれた today. Tapping the yellow word shows: tsukareta, tired.")
        .accessibilityIdentifier("caption-demo")
        .task {
            if reduceMotion { tapped = true; return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.spring(duration: 0.3)) { tapped = true }
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(.easeOut(duration: 0.3)) { tapped = false }
            }
        }
    }
}
