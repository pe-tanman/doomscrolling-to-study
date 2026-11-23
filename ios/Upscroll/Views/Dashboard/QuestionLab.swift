#if DEBUG
import SwiftUI

/// Debug builds only: fire every question type, original, practice mode, curriculum state and reward screen on demand.
struct QuestionLab: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore

    @State private var wordQuery = ""
    @State private var placeIndex = 0
    @State private var phraseIndex = 0
    @State private var skill: Skill = .reading
    @State private var practice: [(phrase: Phrase, skill: Skill)]?
    @State private var showFeedSheet = false
    @State private var showShare = false
    @State private var heard = ""

    private var place: Place { Curriculum.places[min(placeIndex, Curriculum.places.count - 1)] }
    private var phrase: Phrase { place.phrases[min(phraseIndex, place.phrases.count - 1)] }
    private var chosenWord: VocabEntry? {
        let q = wordQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return nil }
        return session.vocab.byId[q] ?? session.vocab.entries.first { $0.kana == q || $0.kanji == q || $0.romaji == q || $0.meaning.lowercased() == q }
    }

    var body: some View {
        Form {
            feedCards
            originals
            practiceSection
            curriculum
            screens
            words
            speech
            voiceSection
        }
        .navigationTitle("Question Lab")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: Binding(get: { practice != nil }, set: { if !$0 { practice = nil } })) {
            LabPracticeRunner(items: practice ?? [], place: place)
        }
        .sheet(isPresented: $showFeedSheet) { JapaneseFeedSheet(session: session, journey: journey) }
        .sheet(isPresented: $showShare) { ShareCardSheet(journey: journey, wordBook: wordBook) }
    }

    // MARK: Feed cards

    private var feedCards: some View {
        Section {
            TextField("Word (id, kana, romaji or meaning) · blank = random", text: $wordQuery)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !wordQuery.isEmpty {
                Text(chosenWord.map { "→ \($0.kana) · \($0.meaning) · N\($0.level)" } ?? "No match: a random word is used")
                    .font(.caption).foregroundStyle(chosenWord == nil ? Brand.warn : Brand.ink2)
            }
            ForEach(LabQuestion.allCases) { q in
                Button { fire { await session.labShow(q, entry: q == .listen ? nil : chosenWord) } } label: {
                    Label(q.rawValue, systemImage: q.symbol)
                }
                .accessibilityIdentifier("lab-\(q)")
            }
            Button { fire { session.labRunNonverbal() } } label: {
                Label("Real pipeline: screenshot → Jev → bonus cards", systemImage: "bolt.horizontal")
            }
        } header: { Text("Feed cards (on the current Short)") } footer: {
            Text("Closes the dashboard and shows the card over the Short. Picture cards use a live screenshot; the outline is a fixed centre box. The real pipeline needs the lesson server.")
        }
    }

    // MARK: Originals & practice

    private var pickers: some View {
        Group {
            Picker("Place", selection: $placeIndex) {
                ForEach(Curriculum.places.indices, id: \.self) { i in Text("\(i + 1) · \(Curriculum.places[i].name)").tag(i) }
            }
            .onChange(of: placeIndex) { _, _ in phraseIndex = 0 }
            Picker("Phrase", selection: $phraseIndex) {
                ForEach(place.phrases.indices, id: \.self) { i in Text(place.phrases[i].pattern).tag(i) }
            }
            Picker("Skill", selection: $skill) {
                ForEach(Skill.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var originals: some View {
        Section("Originals in the feed") {
            pickers
            Button { fire { session.labShowOriginal(phrase, skill: skill) } } label: {
                Label(skill == .listening ? "Show mini-reel" : "Show quest card", systemImage: "sparkles.tv")
            }
            .accessibilityIdentifier("lab-original")
            Button { fire { session.labShowShortPhrase() } } label: {
                Label("Phrase from this Short", systemImage: "text.bubble.fill")
            }
            .accessibilityIdentifier("lab-shortPhrase")
            ForEach([GrammarMode.notice, .cloze, .build], id: \.self) { m in
                Button { fire { session.labShowGrammar(m) } } label: {
                    Label("Grammar chunk · \(m.rawValue)", systemImage: "square.stack.3d.up.fill")
                }
                .accessibilityIdentifier("lab-grammar-\(m.rawValue)")
            }
            Button { fire { session.labShowLessonCheckpoint() } } label: {
                Label("Lesson checkpoint", systemImage: "graduationcap.fill")
            }
            .accessibilityIdentifier("lab-lesson")
        }
    }

    private var practiceSection: some View {
        Section {
            Button("This phrase · \(skill.title)") { practice = [(phrase, skill)] }
            Button("This phrase · all 4 skills") { practice = Skill.allCases.map { (phrase, $0) } }
                .accessibilityIdentifier("lab-phrase-all")
            Button("Whole place · \(skill.title)") { practice = place.phrases.map { ($0, skill) } }
            Button("Whole place · every phrase × skill (\(place.phrases.count * 4))") {
                practice = place.phrases.flatMap { p in Skill.allCases.map { (p, $0) } }
            }
            Button("Every phrase in the curriculum · \(skill.title) (\(Curriculum.allPhrases.count))") {
                practice = Curriculum.allPhrases.map { ($0, skill) }
            }
        } header: { Text("Practice sandbox") } footer: {
            Text("Uses the place and phrase above. Answers here don't change your progress.")
        }
    }

    // MARK: Curriculum state

    private var curriculum: some View {
        Section {
            HStack {
                Text("\(place.name)")
                Spacer()
                Text("\(journey.phrasesDone(place))/\(place.phrases.count) · \(journey.gapCount(place)) gaps · \(stateText)")
                    .font(.caption).foregroundStyle(Brand.ink2)
            }
            Button("Jump to \(place.name) (earlier places done)") { journey.debugMove(to: place) }
            Button("Complete \(place.name)") { journey.debugSet(place, skills: Set(Skill.allCases)) }
            Button("Read + hear only (writing/speaking gaps)") { journey.debugSet(place, skills: [.reading, .listening]) }
            Button("Clear \(place.name)", role: .destructive) { journey.debugSet(place, skills: []) }
            Button("Demo journey (Arrival done, Café half, 6 weeks)") { journey.seedDemo() }
            Button("Reset journey", role: .destructive) { journey.reset() }
        } header: { Text("Curriculum state") } footer: {
            Text("Current place: \(journey.currentPlace.name) · \(journey.stamps.count) stamps · \(journey.souvenirs.count) souvenirs")
        }
    }

    private var stateText: String {
        switch journey.state(place) { case .done: return "done"; case .current: return "current"; case .locked: return "locked" }
    }

    // MARK: Screens & rewards

    private var screens: some View {
        Section {
            Button("Session recap") { session.labRoute = "recap" }
            Button("Daily limit reached (recap + pause)") { fire { session.labHitDailyLimit() } }
            Button("+10 min feed time (40% Japanese)") { journey.debugAddTime(minutes: 10, japaneseShare: 0.4) }
            Button("Make my feed more Japanese") { showFeedSheet = true }
            Button("Share card") { showShare = true }
            Button("New session (reset recap counters)") { session.startNewSession() }
        } header: { Text("Screens & rewards") } footer: {
            let t = journey.today
            Text("Today: \(durationText(t.scrollSeconds)) scrolled · \(durationText(t.japaneseSeconds)) Japanese · limit \(session.settings.dailyLimitMinutes) min")
        }
    }

    private var words: some View {
        Section {
            Button("Make all \(wordBook.words.count) words due") { wordBook.debugMakeAllDue() }
            Picker("Level", selection: $session.settings.jlptLevel) {
                ForEach(JLPT.levels, id: \.self) { Text("N\($0)").tag($0) }
            }
            Button("Reset words", role: .destructive) { wordBook.reset() }
        } header: { Text("Words") } footer: {
            Text("\(wordBook.words.count) met · \(wordBook.learnedCount) learned · \(wordBook.dueWords.count) due")
        }
    }

    // MARK: Speech matcher

    private var speech: some View {
        Section {
            TextField("What the recognizer heard (kana/kanji)", text: $heard)
            let target = phrase.exampleKana
            let ok = SpeechCheck.matches(heard, target: target)
            LabeledContent("Target", value: target)
            LabeledContent("Romaji", value: "\(SpeechCheck.romaji(heard)) vs \(SpeechCheck.romaji(target))")
            LabeledContent("Similarity", value: String(format: "%.2f · %@", SpeechCheck.similarity(SpeechCheck.romaji(heard), SpeechCheck.romaji(target)), ok ? "pass" : "fail"))
        } header: { Text("Say-it matcher") } footer: {
            Text("Checks the speaking grader without a microphone. Pass = romaji contains the target or ≥ 0.75 similar.")
        }
    }

    @AppStorage(Speech.naturalVoiceKey) private var naturalVoice = true
    @State private var cachedClips = Speech.shared.debugCacheCount

    private var voiceSection: some View {
        Section {
            Toggle("Natural voice (Gemini 3.8 Flash TTS)", isOn: $naturalVoice)
            Button("Play phrase: \(phrase.exampleKana)") { Speech.shared.say(phrase.exampleKana); refreshClips() }
                .accessibilityIdentifier("lab-voice-phrase")
            Button("Play word: \(chosenWord?.kana ?? "ねこ")") { Speech.shared.say(chosenWord?.kana ?? "ねこ"); refreshClips() }
            HStack {
                ForEach(["ふ", "を", "り", "きゃ", "ジュ"], id: \.self) { k in
                    Button(k) { Speech.shared.say(k) }.buttonStyle(.bordered).accessibilityIdentifier("lab-kana-\(k)")
                }
            }
            Button("Clear voice cache (\(cachedClips) clips)", role: .destructive) { Speech.shared.debugClearCache(); cachedClips = 0 }
                .accessibilityIdentifier("lab-voice-clear")
        } header: { Text("Voice") } footer: {
            Text("Natural voice needs the lesson server with GEMINI_API_KEY; it waits 2.5 s, then uses the iPhone voice.")
        }
    }

    private func refreshClips() {
        Task { try? await Task.sleep(for: .seconds(3)); cachedClips = Speech.shared.debugCacheCount }
    }

    /// Close the dashboard, then run `action` once the sheet is gone.
    private func fire(_ action: @escaping () async -> Void) {
        session.labRoute = "close"
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await action()
        }
    }
}

/// Runs practice items one after another without touching progress.
struct LabPracticeRunner: View {
    let items: [(phrase: Phrase, skill: Skill)]
    let place: Place
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var right = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline) }
                    .accessibilityLabel("Close")
                Spacer()
                Text("\(min(index + 1, items.count)) / \(items.count) · \(right) right").font(.subheadline.monospacedDigit())
                Spacer()
                Button("Skip") { index += 1 }.disabled(index >= items.count)
            }
            .foregroundStyle(Brand.ink)
            if index < items.count {
                let it = items[index]
                Text("\(it.skill.title) · \(it.phrase.pattern)").font(.caption).foregroundStyle(Brand.ink3)
                ScrollView {
                    PhrasePractice(phrase: it.phrase, skill: it.skill, place: Curriculum.place(of: it.phrase.id) ?? place) { ok in
                        if ok { right += 1 }
                        index += 1
                    }
                    .id(index)
                    .brandCard()
                }
            } else {
                Spacer()
                Text("Done · \(right) of \(items.count) right").font(.title2.weight(.bold))
                Button("Again") { index = 0; right = 0 }.buttonStyle(.brandSecondary)
                Spacer()
            }
        }
        .padding(16)
        .background(Brand.sky.ignoresSafeArea())
    }
}
#endif
