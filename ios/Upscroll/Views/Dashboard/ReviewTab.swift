import SwiftUI

/// Review of collected words. Questions get harder as a word gets stronger (a difficulty ladder):
/// 1. Recognize: see or hear the Japanese, pick the meaning.
/// 2. Choose and build: pick the Japanese for a meaning, fill the real line from the Short, spell it from kana tiles.
/// 3. Produce from memory: recall it unaided and rate yourself, spell what you hear, or say it out loud.
/// A missed word comes back two questions later in the same set (practice only, the schedule already counted the miss).
struct ReviewTab: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook

    enum Kind: String, CaseIterable, Identifiable {
        case readMeaning = "Meaning"
        case listenMeaning = "Listening"
        case meaningToJapanese = "Pick the Japanese"
        case fillBlank = "Fill the line"
        case spell = "Spell it"
        case dictation = "Hear & spell"
        case recallCard = "Recall"
        case sayIt = "Say it"
        case kanaSound = "Kana sounds"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .readMeaning: return "text.book.closed.fill"
            case .listenMeaning: return "ear.fill"
            case .meaningToJapanese: return "bubble.left.fill"
            case .fillBlank: return "text.insert"
            case .spell: return "square.grid.3x2.fill"
            case .dictation: return "ear.and.waveform"
            case .recallCard: return "brain.head.profile"
            case .sayIt: return "mic.fill"
            case .kanaSound: return "character.ja"
            }
        }
        var usesOptions: Bool { [.readMeaning, .listenMeaning, .meaningToJapanese, .fillBlank, .kanaSound].contains(self) }
        var usesTiles: Bool { self == .spell || self == .dictation }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case mix = "Mix", recall = "Recall", listen = "Listen", context = "In context"
        var id: String { rawValue }
        /// nil: pick by how strong each word is (the ladder).
        var kinds: [Kind]? {
            switch self {
            case .mix: return nil
            case .recall: return [.recallCard, .spell, .meaningToJapanese, .sayIt]
            case .listen: return [.listenMeaning, .dictation, .sayIt]
            case .context: return [.fillBlank]
            }
        }
    }

    struct Option: Identifiable, Equatable {
        let id: String
        let title: String
        var subtitle: String? = nil
        var emoji: String? = nil
    }

    struct Question: Equatable {
        let entry: VocabEntry
        let kind: Kind
        var options: [Option] = []
        var answerId: String = ""
        /// Fill-the-blank: the line with the word cut out. Kana: the character asked about.
        var prompt: String? = nil
        var japaneseLine: String? = nil
        /// Spelling: the shuffled tile bank and the right order.
        var tiles: [String] = []
        var answerTiles: [String] = []
        /// Missed earlier in this set: practice again, not counted on the schedule.
        var isRetry = false
    }

    @State private var mode: Mode = .mix
    @State private var question: Question?
    /// Multiple choice: the option tapped.
    @State private var picked: String?
    /// Every kind: right or wrong once answered.
    @State private var outcome: Bool?
    @State private var placed: [Int] = []
    @State private var revealed = false
    @StateObject private var speech = SpeechCheck()
    /// "Can't speak now": no more speaking questions this visit.
    @State private var speakingOff = false
    @State private var askedAt = Date()
    /// Nothing due: the learner chose to practice anyway (early reviews barely move the schedule).
    @State private var practiceAnyway = false
    @State private var right = 0
    @State private var answered = 0
    @State private var retries: [(id: String, at: Int)] = []
    @State private var lastKind: Kind?
    /// A quick set fits a short break ("about 1 min" in Learn); you can stop after it or keep going.
    static let quickSet = 5

    private var level: ScriptLevel { session.settings.scriptLevel }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Practice", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in next() }

                if let q = question {
                    scoreBar(q)
                    prompt(q)
                        .answerEffects()
                    if let note = q.entry.suffixNote {
                        Label(note, systemImage: "info.circle").font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("suffix-note")
                    }
                    answerArea(q)
                    if outcome != nil { afterAnswer(q) }
                } else if wordBook.words.isEmpty {
                    ContentUnavailableView(mode == .context ? "No lines to practice yet" : "Nothing to review yet",
                                           systemImage: "rectangle.stack",
                                           description: Text("Scroll some Shorts. Words you meet become review cards."))
                } else {
                    caughtUp
                }
            }
            .padding()
        }
        .background(Brand.sky)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeOut(duration: 0.2), value: outcome)
        .animation(.easeOut(duration: 0.2), value: revealed)
        .onAppear { if question == nil { next() } }
        .onDisappear {
            speech.stop()
            guard answered > 0 else { return }
            let left = wordBook.dueWords.count
            wordBook.lastReviewSummary = "You reviewed \(answered) (\(right) right)" + (left > 0 ? " · \(left) left for later" : " · all caught up!")
        }
        .onChange(of: speech.state) { _, s in
            if case .heard(_, true) = s, let q = question, q.kind == .sayIt { grade(q, correct: true) }
        }
    }

    /// The sentence of a translated caption that holds the word (else the first one), without trailing fragments.
    static func firstSentence(containing e: VocabEntry) -> (String) -> String {
        { ja in
            var parts: [String] = []
            var cur = ""
            for ch in ja {
                cur.append(ch)
                if "。？！?!".contains(ch) { parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            }
            let tail = cur.trimmingCharacters(in: .whitespaces)
            if !tail.isEmpty { parts.append(tail) }
            let hit = parts.first { VocabStore.range(of: e, inJapanese: $0) != nil }
            return hit ?? parts.first ?? ja
        }
    }

    private func scoreBar(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(q.kind.rawValue, systemImage: q.kind.symbol).foregroundStyle(Brand.violetDeep)
                if q.isRetry {
                    Text("AGAIN").font(.caption2.weight(.heavy)).foregroundStyle(Brand.warn)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Brand.warn.opacity(0.15), in: Capsule())
                        .accessibilityIdentifier("retry-chip")
                }
                Spacer()
                Label("\(wordBook.dueWords.count) due", systemImage: "clock.fill").foregroundStyle(Brand.violetDeep)
                    .accessibilityLabel("\(wordBook.dueWords.count) words still due for review")
                Text("· \(right)/\(answered)")
                    .accessibilityLabel("This round: \(right) of \(answered) answers right")
            }
            .font(.subheadline.weight(.semibold))
            if answered < Self.quickSet {
                ProgressView(value: Double(answered), total: Double(Self.quickSet)).tint(Brand.violet)
                    .accessibilityLabel("Quick set \(answered) of \(Self.quickSet)")
            }
        }
    }

    // MARK: Prompt

    @ViewBuilder
    private func prompt(_ q: Question) -> some View {
        let done = outcome != nil
        VStack(spacing: 12) {
            switch q.kind {
            case .readMeaning:
                Text("What does this mean?").font(.subheadline)
                let shown = level.display(q.entry)
                // Loanwords: romaji ("pan") spells the English answer, so it's hidden until you answer.
                if let sub = shown.sub, !(q.entry.loanword && !done) { Text(sub).font(.title3) }
                Text(shown.main).font(.system(size: 52, weight: .heavy, design: .rounded))
                hearButton(q.entry.mainKana)
            case .listenMeaning:
                Text("Listen. What does it mean?").font(.subheadline)
                bigSpeaker(q.entry.mainKana)
                if done { Text(level.display(q.entry).main).font(.title.weight(.bold)) }
            case .meaningToJapanese, .spell, .recallCard, .sayIt:
                Text(q.kind == .spell ? "Spell it in kana" : q.kind == .sayIt ? "Say it in Japanese" : "How do you say…")
                    .font(.subheadline)
                if !q.entry.emoji.isEmpty { Text(q.entry.emoji).font(.system(size: 56)) }
                Text(session.vocab.shortMeaning(q.entry)).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                // Spelling has one set of tiles: when several words mean this, say which one.
                if q.kind == .spell, !(done || revealed), let hint = session.vocab.whichWordHint(for: q.entry) {
                    Text(hint).font(.subheadline).foregroundStyle(Brand.ink2).accessibilityIdentifier("spell-hint")
                }
                if done || revealed { answerReveal(q) }
            case .dictation:
                Text("Write what you hear").font(.subheadline)
                bigSpeaker(q.entry.mainKana)
                Button { Speech.shared.saySlowly(q.entry.mainKana) } label: {
                    Label("Slowly", systemImage: "tortoise.fill").font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(Brand.violet)
                if done { answerReveal(q) }
            case .fillBlank:
                Text("Which Japanese word fits the line from your Short?")
                    .font(.subheadline).multilineTextAlignment(.center)
                Text(!done ? AttributedString(q.prompt ?? "") : filledLine(q))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if done, let ja = q.japaneseLine.map(Self.firstSentence(containing: q.entry)) {
                    // One sentence (no leftovers from the next caption), with romaji at the beginner levels.
                    VStack(spacing: 2) {
                        Text(ja).font(.body).multilineTextAlignment(.center)
                        if level.rawValue <= ScriptLevel.kanaRomaji.rawValue {
                            Text(Romanize.pronounced(ja)).font(.subheadline).multilineTextAlignment(.center)
                        }
                    }
                }
            case .kanaSound:
                Text("What sound is this?").font(.subheadline)
                Text(q.prompt ?? "").font(.system(size: 80, weight: .bold))
                Text(!done ? "This kana is in a word you met \(q.entry.emoji)" : "\(q.entry.kana) = \(q.entry.romaji) · \(q.entry.meaning)")
                    .font(.subheadline)
                if done { hearButton(q.prompt ?? "") }
            }
            if q.kind != .fillBlank, done, let c = wordBook.progress(q.entry.id)?.contexts.first, !c.line.isEmpty {
                // Where it was met: ties the word back to the Short.
                Text(highlighted(c.line, entry: q.entry, vocab: session.vocab))
                    .font(.subheadline).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// The Japanese, its reading and a replay, shown once the learner has committed to an answer.
    private func answerReveal(_ q: Question) -> some View {
        let shown = level.display(q.entry)
        return VStack(spacing: 4) {
            Text(shown.main).font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Brand.violetDeep)
            Text(q.entry.mainKana == shown.main ? q.entry.romaji : "\(q.entry.mainKana) · \(q.entry.romaji)")
                .font(.subheadline)
            hearButton(q.entry.mainKana)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("answer-reveal")
    }

    // MARK: Answer area

    @ViewBuilder
    private func answerArea(_ q: Question) -> some View {
        switch q.kind {
        case let k where k.usesOptions:
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(q.options) { option(q, $0) }
            }
        case .spell, .dictation:
            tileBuilder(q)
        case .recallCard:
            recallControls(q)
        case .sayIt:
            sayControls(q)
        default:
            EmptyView()
        }
    }

    private func option(_ q: Question, _ o: Option) -> some View {
        let isAnswer = o.id == q.answerId
        let state: Color? = picked == nil ? nil : (isAnswer ? Brand.success : (picked == o.id ? Brand.danger : nil))
        return Button {
            guard picked == nil else { return }
            picked = o.id
            grade(q, correct: isAnswer)
        } label: {
            VStack(spacing: 4) {
                if let e = o.emoji, !e.isEmpty { Text(e).font(.title2) }
                Text(o.title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                if let sub = o.subtitle { Text(sub).font(.subheadline) }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background((state ?? Brand.surface).opacity(state == nil ? 1 : 0.25),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(state ?? .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review-option")
    }

    /// Spell / hear & spell: tap kana tiles in order, tap a placed tile to take it back, then Check.
    private func tileBuilder(_ q: Question) -> some View {
        // Romaji under the tiles while the word is new-ish; hidden for hear & spell (the sound is the test).
        let romaji = q.kind == .spell && (wordBook.progress(q.entry.id)?.correct ?? 0) < 3
        return VStack(alignment: .leading, spacing: 12) {
            FlowTiles(items: placed.map { q.tiles[$0] }, style: .placed, placeholder: placed.count < q.answerTiles.count, romaji: romaji) { i in
                if outcome == nil { placed.remove(at: i) }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if let ok = outcome {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(ok ? Brand.success : Brand.danger, lineWidth: 2)
                }
            }
            FlowTiles(items: q.tiles, style: .bank, used: Set(placed), romaji: romaji) { i in
                guard outcome == nil, !placed.contains(i), placed.count < q.answerTiles.count else { return }
                placed.append(i)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            if outcome == nil {
                HStack {
                    Button { grade(q, correct: false) } label: {
                        Label("I don't know", systemImage: "eye.fill").labelStyle(.iconOnly).font(.title3)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Check") { grade(q, correct: placed.map { q.tiles[$0] } == q.answerTiles) }
                        .buttonStyle(.borderedProminent).tint(Brand.violet)
                        .disabled(placed.count < q.answerTiles.count)
                        .accessibilityIdentifier("spell-check")
                }
            }
        }
    }

    /// Recall card: think of the Japanese first, then reveal and rate honestly.
    @ViewBuilder
    private func recallControls(_ q: Question) -> some View {
        if !revealed {
            VStack(spacing: 8) {
                Button {
                    revealed = true
                    Speech.shared.say(q.entry.mainKana)
                } label: {
                    Label("Show answer", systemImage: "eye.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent).tint(Brand.violet)
                .accessibilityIdentifier("show-answer")
            }
        } else if outcome == nil {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    rateButton("Forgot", "xmark", Brand.danger) { grade(q, correct: false) }
                    rateButton("Hard", "tortoise.fill", Brand.warn) { grade(q, correct: true, easy: false) }
                    rateButton("Easy", "bolt.fill", Brand.success) { grade(q, correct: true, easy: true) }
                }
            }
        }
    }

    private func rateButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered).tint(color)
        .accessibilityIdentifier("rate-\(title.lowercased())")
    }

    /// Say it: on-device speech recognition checks the word.
    @ViewBuilder
    private func sayControls(_ q: Question) -> some View {
        VStack(spacing: 12) {
            Button {
                if speech.state == .listening { speech.stop() } else { Task { await speech.start(target: q.entry.mainKana, alternatives: session.vocab.equivalents(of: q.entry).map(\.mainKana)) } }
            } label: {
                Image(systemName: speech.state == .listening ? "stop.fill" : "mic.fill")
                    .font(.title).foregroundStyle(.white)
                    .frame(width: 80, height: 80)
                    .background(Brand.violet, in: Circle())
                    .scaleEffect(1 + CGFloat(speech.level) * 0.15)
            }
            .buttonStyle(.plain)
            .disabled(outcome != nil)
            .accessibilityLabel(speech.state == .listening ? "Stop listening" : "Start speaking")
            .accessibilityIdentifier("say-mic")
            switch speech.state {
            case .idle: EmptyView()
            case .listening: Image(systemName: "waveform").font(.title2).foregroundStyle(Brand.violet).symbolEffect(.variableColor.iterative)
            case .heard(let t, let ok):
                Label("「\(t)」", systemImage: ok ? "checkmark.circle.fill" : "arrow.clockwise")
                    .font(.title3).foregroundStyle(ok ? Brand.success : .primary)
                if ok, let alt = speech.heardAlternative {
                    Text("\(alt) is right too · this card's word is \(q.entry.mainKana)")
                        .font(.subheadline).foregroundStyle(Brand.ink2)
                        .accessibilityIdentifier("say-alternative")
                }
            case .denied, .unavailable:
                Image(systemName: "mic.slash.fill").font(.title2)
                    .accessibilityLabel("Speech recognition isn't available")
            }
            if outcome == nil {
                HStack {
                    Button { speech.stop(); speakingOff = true; next() } label: {
                        Label("Can't speak now", systemImage: "speaker.slash.fill").labelStyle(.iconOnly).font(.title3)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button { speech.stop(); grade(q, correct: false) } label: {
                        Label("Show answer", systemImage: "eye.fill").labelStyle(.iconOnly).font(.title3)
                    }
                    .buttonStyle(.bordered).tint(Brand.violet)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func afterAnswer(_ q: Question) -> some View {
        let ok = outcome == true
        if answered > 0, answered % Self.quickSet == 0 {
            Label("\(answered) done", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.success)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("quick-set-done")
        }
        // What happened to this word: answered words leave the "due" count and come back on schedule.
        let due = wordBook.progress(q.entry.id)?.due
        let when = due.map { $0.formatted(.relative(presentation: .named)) } ?? "soon"
        // Right/wrong + when it comes back (a missed word also returns later in this set).
        Label(q.kind == .kanaSound ? (ok ? "Right" : "Not quite") : (!ok && !q.isRetry ? "Again soon" : when),
              systemImage: ok ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ok ? Brand.success : Brand.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)   // wrap, never clip
            .accessibilityIdentifier("review-next-check")
        Button { next() } label: {
            Label("Next", systemImage: "arrow.right")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Brand.violet)
        .transition(.opacity)
    }

    private func filledLine(_ q: Question) -> AttributedString {
        guard let c = wordBook.progress(q.entry.id)?.contexts.first else { return AttributedString(q.prompt ?? "") }
        return highlighted(c.line, entry: q.entry, vocab: session.vocab)
    }

    private func hearButton(_ text: String) -> some View {
        Button { Speech.shared.say(text) } label: { Label("Hear", systemImage: "speaker.wave.2.fill") }
            .buttonStyle(.bordered)
            .tint(Brand.violet)
    }

    private func bigSpeaker(_ text: String) -> some View {
        Button { Speech.shared.say(text) } label: {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 40))
                .frame(width: 110, height: 110)
                .background(Brand.violetSoft, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.violet)
        .accessibilityLabel("Play the word")
    }

    // MARK: Grading

    private func grade(_ q: Question, correct: Bool, easy: Bool? = nil) {
        guard outcome == nil else { return }
        outcome = correct
        answered += 1
        if correct { right += 1 }
        if q.kind == .kanaSound, correct, let k = q.prompt { KanaProgress.shared.recordRight(k) }
        if q.kind != .kanaSound && !q.isRetry {
            // Building or saying takes longer than tapping, so "easy" allows more time there.
            let limit = q.kind.usesOptions ? Memory.easySeconds : 8
            let isEasy = easy ?? (correct && Date().timeIntervalSince(askedAt) <= limit)
            wordBook.recordAnswer(q.entry.id, correct: correct, easy: isEasy)
            if !correct { retries.append((q.entry.id, answered + 2)) }
        }
        SoundFX.answer(correct: correct)
        switch q.kind {
        case .kanaSound: Speech.shared.say(q.prompt ?? "")
        case .listenMeaning, .recallCard: break   // already heard
        default: Speech.shared.say(q.entry.mainKana)
        }
    }

    // MARK: Building questions

    /// 0: not answered right yet → recognize. 1: getting there → choose and build. 2: strong → produce.
    static func stage(_ p: WordProgress) -> Int { p.reviewStage }

    static func ladder(_ stage: Int) -> [Kind] {
        switch stage {
        case 0: return [.readMeaning, .listenMeaning, .readMeaning, .kanaSound]
        case 1: return [.meaningToJapanese, .spell, .fillBlank, .listenMeaning]
        default: return [.recallCard, .dictation, .sayIt, .spell, .fillBlank]
        }
    }

    private var canSpeak: Bool { !speakingOff && !SpeechCheck.permissionDenied }

    private func reset() {
        picked = nil; outcome = nil; placed = []; revealed = false
        speech.stop()
        askedAt = Date()
    }

    private func next() {
        reset()
        let modeKinds = mode.kinds.map { kinds in kinds.filter { $0 != .sayIt || canSpeak } }

        // A word missed earlier in this set, asked a different way.
        if let i = retries.firstIndex(where: { $0.at <= answered }) {
            let id = retries.remove(at: i).id
            if let p = wordBook.progress(id), let e = session.vocab.byId[id] {
                let kinds = (modeKinds ?? [.meaningToJapanese, .spell, .readMeaning]).shuffled()
                for k in kinds where k != lastKind {
                    if var q = build(k, entry: e, progress: p) { q.isRetry = true; show(q); return }
                }
            }
        }

        // Forgetting curve: only due words, most forgotten first. Nothing due → "All caught up",
        // unless the learner asked to practice anyway (then the least-remembered words).
        var pool = wordBook.dueWords.sorted { $0.recallNow < $1.recallNow }
        if pool.isEmpty && practiceAnyway {
            pool = Array(wordBook.list(.learning).sorted { $0.recallNow < $1.recallNow }.prefix(12))
        }
        let all = pool.compactMap { p in session.vocab.byId[p.id].map { (p, $0) } }
        let fresh = all.filter { $0.1.id != question?.entry.id }
        // Mostly the most-forgotten few, with a little variety.
        let candidates = Array((fresh.isEmpty ? all : fresh).prefix(4)).shuffled()

        for (p, e) in candidates {
            var kinds = (modeKinds ?? Self.ladder(Self.stage(p))).filter { $0 != .sayIt || canSpeak }.shuffled()
            // Avoid the same type twice in a row when there's a choice.
            if kinds.count > 1, let last = lastKind, kinds.first == last { kinds.append(kinds.removeFirst()) }
            for k in kinds {
                if let q = build(k, entry: e, progress: p) { show(q); return }
            }
        }
        // Nothing fit (e.g. "In context" with no usable lines): any kind for any word.
        for (p, e) in candidates {
            for k in [Kind.readMeaning, .meaningToJapanese] {
                if let q = build(k, entry: e, progress: p) { show(q); return }
            }
        }
        question = nil
    }

    private func show(_ q: Question) {
        question = q
        lastKind = q.kind
        if q.kind == .listenMeaning || q.kind == .dictation { Speech.shared.say(q.entry.mainKana) }
        else { Speech.shared.prefetch(q.entry.mainKana) }
    }

    /// Nothing is due: reviewing now would be too early to help memory.
    private var caughtUp: some View {
        let nextDue = wordBook.words.values.map(\.due).filter { $0 > Date() }.min()
        return ContentUnavailableView {
            Label("Nothing due right now", systemImage: "checkmark.seal.fill")
        } description: {
            Text(nextDue.map { "Words come back when they're due. Next review \($0.formatted(.relative(presentation: .named)))." }
                 ?? "Words come back when they're due.")
        } actions: {
            Button("Practice anyway") { practiceAnyway = true; next() }
                .buttonStyle(.bordered)
        }
    }

    private func wordOption(_ e: VocabEntry) -> Option {
        let shown = level.display(e)
        return Option(id: e.id, title: shown.main, subtitle: shown.sub)
    }

    private func build(_ kind: Kind, entry e: VocabEntry, progress p: WordProgress) -> Question? {
        let others = session.vocab.distractors(for: e, count: 3)
        switch kind {
        case .readMeaning, .listenMeaning:
            let opts = (others + [e]).shuffled().map { Option(id: $0.id, title: session.vocab.shortMeaning($0), emoji: kind == .readMeaning ? nil : $0.emoji) }
            return Question(entry: e, kind: kind, options: opts, answerId: e.id)
        case .meaningToJapanese:
            return Question(entry: e, kind: kind, options: (others + [e]).shuffled().map(wordOption), answerId: e.id)
        case .fillBlank:
            // Cut the word out of the most readable real line it was met in; skip choppy caption fragments.
            func readable(_ l: String) -> Int {
                let words = l.split(separator: " ").count
                let starts = l.first.map { $0.isUppercase } ?? false
                let ends = l.last.map { ".!?…".contains($0) } ?? false
                return words + (starts ? 4 : 0) + (ends ? 4 : 0)
            }
            let usable = p.contexts.filter { !$0.line.contains("Spotted in") && !$0.line.contains(" in that Short") }
                .compactMap { c in session.vocab.candidates(in: c.line, allSenses: true).first(where: { $0.entry.id == e.id }).map { (c, $0) } }
            guard let (c, m) = usable.max(by: { readable($0.0.line) < readable($1.0.line) }),
                  readable(c.line) >= 10 else { return nil }
            let blanked = c.line.replacingCharacters(in: m.range, with: "_____")
            // Same-shape choices so the sentence doesn't give it away (こんな vs そんな/あんな/どんな, not サラダ).
            let fitOthers = session.vocab.sameShapeDistractors(for: e, count: 3)
            return Question(entry: e, kind: kind, options: (fitOthers + [e]).shuffled().map(wordOption),
                            answerId: e.id, prompt: blanked, japaneseLine: c.japaneseLine)
        case .spell, .dictation:
            guard !e.isSuffix, let t = Kana.spellTiles(for: e.mainKana, extra: kind == .dictation ? 3 : 2) else { return nil }
            return Question(entry: e, kind: kind, tiles: t.tiles, answerTiles: t.answer)
        case .recallCard:
            return Question(entry: e, kind: kind)
        case .sayIt:
            guard canSpeak, !e.isSuffix, e.mainKana.count >= 2 else { return nil }
            return Question(entry: e, kind: kind)
        case .kanaSound:
            let units = Kana.units(e.kana).filter { $0.note == nil }
            guard let u = units.randomElement() else { return nil }
            var sounds = Set([u.romaji])
            var opts = [Option(id: u.romaji, title: u.romaji)]
            for k in Kana.basicHiragana.shuffled() where opts.count < 4 {
                let r = Kana.romaji(k)
                if sounds.insert(r).inserted { opts.append(Option(id: r, title: r)) }
            }
            return Question(entry: e, kind: kind, options: opts.shuffled(), answerId: u.romaji, prompt: u.kana)
        }
    }
}
