import SwiftUI

/// Shown when the video pauses on a learning word.
/// New word: tap the word → hear it → meaning, how to read it, the Japanese line.
/// Word met before: pick its meaning first (recall), then the same reveal.
struct LearningCard: View {
    let moment: LearningMoment
    @ObservedObject var session: FeedSession
    @ObservedObject private var rewards = Rewards.shared
    @State private var revealed = false
    @State private var picked: String?
    /// When the question appeared: a quick right answer counts as easy recall.
    @State private var askedAt = Date()
    /// Spell cards: tile indices placed so far.
    @State private var placed: [Int] = []
    @StateObject private var speech = SpeechCheck()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Big Japanese word scales with the user's text size (Dynamic Type).
    @ScaledMetric(relativeTo: .largeTitle) private var wordSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var emojiSize: CGFloat = 40
    // Collapsible sections; the learner's choice sticks across cards.
    @AppStorage("card.readingOpen") private var readingOpen = false
    @AppStorage("card.exampleOpen") private var exampleOpen = false

    private var level: ScriptLevel { session.settings.scriptLevel }
    /// Any card that asks before it shows (recall, listen, picture, review).
    private var isRecall: Bool { moment.kind.isQuiz }
    private var isReview: Bool { moment.kind.isReview }

    // See-through Liquid Glass card (iPhone default look). A light dark tint on the glass and
    // darker inner panels keep white text readable over bright video frames.
    /// Dark enough that white text stays legible over bright video frames without any text shadow.
    private let glassTint = Color.black.opacity(0.5)
    private let panelBG = Color.black.opacity(0.24)
    private let accent = Brand.OnDark.gold

    /// Picture questions: the analyzed frame, full size, exactly over the (paused) video.
    private var overlayFrame: (image: UIImage, rect: CGRect, box: CGRect?)? {
        if case .picture(_, _, let f?, let r?, let box) = moment.kind { return (f, r, box) }
        return nil
    }

    /// Keep the outlined thing visible: card on top when the outline is in the lower half of the screen.
    private var cardOnTop: Bool {
        guard let o = overlayFrame, let b = o.box else { return false }
        let midY = o.rect.minY + b.midY * o.rect.height
        return midY > UIScreen.main.bounds.height * 0.5
    }

    var body: some View {
        ZStack(alignment: cardOnTop ? .top : .bottom) {
            if let o = overlayFrame {
                // Every picture question outlines the thing it's about, from the start.
                FrameOverlay(image: o.image, rect: o.rect, box: o.box, accent: accent, showBox: true)
            }
            // Title cards: dim the page more until revealed, so YouTube's English title below doesn't give the word away.
            Color.black.opacity(overlayFrame != nil ? 0 : (moment.fromTitle && !revealed ? 0.6 : 0.15))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { if revealed { session.finishMoment() } }

            ViewThatFits(in: .vertical) {
                cardContent
                ScrollView { cardContent }.scrollBounceBehavior(.basedOnSize)
            }
            .glass(cornerRadius: 32, tint: glassTint)
            .answerEffects()
            .padding(.horizontal, 12)
            .padding(.top, 60)
            .padding(.bottom, 24)
            .environment(\.colorScheme, .dark)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: revealed)
        .onDisappear { speech.stop() }
        .onChange(of: speech.state) { _, s in
            if case .heard(_, true) = s, case .say = moment.kind { answer(correct: true) }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-autoReveal") { revealed = true }
            #endif
        }
    }

    private var cardContent: some View {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if hasLine { englishLine }
                    if isRecall && !revealed {
                        recallQuestion
                    } else {
                        wordButton
                    }
                    if revealed {
                        reveal.transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if !isRecall {
                        Image(systemName: "hand.tap.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, options: .repeat(2))
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Tap the word to hear it and see its meaning")
                    }
                    if revealed { actions }
                }
                .padding(20)
    }

    // MARK: Header + English line

    private var header: some View {
        HStack(spacing: 8) {
            if moment.totalInVideo > 1 {
                Text("\(moment.numberInVideo)/\(moment.totalInVideo)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(accent, in: Capsule())
                    .foregroundStyle(.black)
                    .accessibilityLabel("Word \(moment.numberInVideo) of \(moment.totalInVideo)")
            }
            switch moment.kind {
            case .recall: tag("REMEMBER IT?", Brand.OnDark.cyan)
            case .listen: tag("LISTEN", Brand.OnDark.peach)
            case .picture: tag("PICTURE", Brand.OnDark.mint)
            case .review: tag("REVIEW", Brand.OnDark.violet)
            case .hearIt: tag("REVIEW · LISTEN", Brand.OnDark.violet)
            case .spell: tag("REVIEW · SPELL IT", Brand.OnDark.violet)
            case .say: tag("REVIEW · SAY IT", Brand.OnDark.violet)
            case .learn: EmptyView()
            }
            if case .learn = moment.kind, (session.wordBook.progress(moment.entry.id)?.timesSeen ?? 0) <= 1 {
                tag("NEW", Brand.OnDark.pink)
            }
            if moment.entry.level < session.settings.jlptLevel {
                // Above the level you're learning: fine to meet, flagged so it doesn't feel like a must-know.
                tag("BONUS · N\(moment.entry.level)", Brand.OnDark.gray)
            }
            if moment.entry.loanword, !isRecall || picked != nil {   // a hint when you must produce it
                // Honest label: you know the meaning already; the lesson is reading katakana.
                tag("KATAKANA · FROM ENGLISH", Brand.OnDark.lime)
            }
            Spacer()
            // Skip ticket (earned): skip this quiz without it counting as a miss; the word comes back tomorrow.
            if isRecall && picked == nil && rewards.skips > 0 {
                Button {
                    if rewards.useSkip() {
                        session.wordBook.postpone(moment.entry.id)
                        session.finishMoment()
                    }
                } label: {
                    Label("\(rewards.skips)", systemImage: RewardIcon.skip.symbol)
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 32)
                        .glass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use a skip ticket, \(rewards.skips) left. No miss is counted.")
                .accessibilityIdentifier("use-skip")
            }
            // Close = skip and keep watching (standard top-trailing dismiss, always reachable).
            Button { session.finishMoment() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .glass(in: Circle(), interactive: true)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -6)
            .accessibilityLabel(revealed ? "Close and keep watching" : "Skip this word")
            .accessibilityHint("Closes the card and resumes the video. The word stays in today's pickups.")
            .accessibilityIdentifier("skip")
        }
    }

    private func tag(_ s: String, _ c: Color) -> some View {
        Text(s)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(c, in: Capsule())
            .foregroundStyle(.black)
    }

    private var hasLine: Bool {
        switch moment.kind {
        case .listen, .picture, .hearIt: return false
        default: return !moment.line.isEmpty
        }
    }

    private var englishLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch moment.kind {
            case .review(_, _, let metIn), .spell(_, _, let metIn), .say(let metIn), .hearIt(_, let metIn):
                // Name the earlier Short explicitly: the clip behind the card is a different one.
                sectionLabel(metIn.isEmpty ? "Earlier Short" : maskAnswer(metIn), symbol: "clock.arrow.circlepath")
                    .lineLimit(1)
            default:
                sectionLabel(moment.fromTitle ? "Title" : "",
                             symbol: moment.fromTitle ? "textformat" : "quote.opening")
            }
            Text(lineWithSwap)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Before answering, hide the English answer anywhere on the card (titles, hashtags like #funny).
    private func maskAnswer(_ t: String) -> String {
        guard isRecall && picked == nil && !revealed else { return t }
        var out = t
        // Asked for the Japanese: hide it as "…" (writing the kana in would hand over the answer).
        let replacement = moment.kind.isProduction ? "…" : moment.entry.kana
        let forms = moment.entry.en + moment.entry.meaning.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for form in Set(forms) where form.count >= 2 {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: form) + "\\b"
            out = out.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    private var lineWithSwap: AttributedString {
        guard let r = moment.swapRange else { return AttributedString(moment.line) }
        // Caption speaker-change marks (">>") are noise on the card.
        var head = String(moment.line[moment.line.startIndex..<r.lowerBound])
        while head.hasPrefix(">") || head.hasPrefix(" ") { head.removeFirst() }
        // Recall questions: hide the English answer if the line repeats it ("わあ! WOW! WOW!").
        func hideAnswer(_ t: String) -> String {
            // English → Japanese: the English is the question, so it stays.
            guard isRecall && !revealed && !moment.kind.isProduction else { return t }
            var out = t
            for form in moment.entry.en where !form.isEmpty {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: form) + "\\b"
                out = out.replacingOccurrences(of: pattern, with: moment.entry.kana, options: [.regularExpression, .caseInsensitive])
            }
            return out
        }
        head = hideAnswer(head)
        var before = AttributedString(head)
        // Word joiners between characters: the highlighted word never wraps mid-word (か / ばん).
        // English → Japanese, before answering: the original English word is highlighted (the Japanese is the answer).
        let askEnglish = moment.kind.isProduction && !revealed
        let shownWord = askEnglish ? String(moment.line[r]) : level.display(moment.entry).main
        var word = AttributedString(shownWord.map(String.init).joined(separator: "\u{2060}"))
        word.foregroundColor = accent
        word.font = .title3.weight(.heavy)
        // Before reveal, recall cards hide the meaning, so the original English word is not shown.
        let after = AttributedString(hideAnswer(String(moment.line[r.upperBound...])))
        before.append(word)
        before.append(after)
        return before
    }

    @ViewBuilder private func sectionLabel(_ s: String, symbol: String) -> some View {
        if s.isEmpty {
            Image(systemName: symbol).font(.subheadline.weight(.bold)).foregroundStyle(.white)
        } else {
            Label(s, systemImage: symbol).font(.subheadline.weight(.bold)).foregroundStyle(.white)
        }
    }

    // MARK: Word

    private var wordButton: some View {
        let shown = level.display(moment.entry)
        return Button {
            session.hearMoment()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            revealed = true
        } label: {
            HStack(spacing: 14) {
                if !moment.entry.emoji.isEmpty {   // JLPT-list words have no emoji
                    Text(moment.entry.emoji).font(.system(size: emojiSize)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let sub = shown.sub {
                        Text(sub).font(.headline).foregroundStyle(.white)
                    }
                    Text(shown.main)
                        .font(.system(size: wordSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(accent)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundStyle(.black)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !revealed && !reduceMotion)
                    .frame(width: 52, height: 52)
                    .background(accent, in: Circle())
            }
            .padding(14)
            .background(panelBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(moment.entry.kana), \(moment.entry.romaji)")
        .accessibilityHint(revealed ? "Plays the word again" : "Plays the word and shows its meaning")
        .accessibilityIdentifier("word-button")
    }

    // MARK: Recall (word met before)

    private var recallQuestion: some View {
        let shown = level.display(moment.entry)
        let options = moment.kind.options
        return VStack(alignment: .leading, spacing: 10) {
            switch moment.kind {
            case .listen(_, let kanaDrill):
                listenPrompt(kanaDrill: kanaDrill)
            case .picture(_, let ask, let frame, let rect, let box):
                pictureQuestion(ask: ask, frame: rect == nil ? frame : nil, box: box)
            case .review(_, true, _), .recall(_, true):
                Text("How do you say \"\(session.vocab.shortMeaning(moment.entry))\" in Japanese?")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("ask-japanese")
                // No "starts with お" hint here: other words with the same meaning are never options, and the hint
                // would point straight at the answer.
            case .hearIt:
                hearItPrompt
            case .spell(let tiles, let answer, _):
                spellQuestion(tiles: tiles, answer: answer)
            case .say:
                sayQuestion
            default:
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        // Loanwords: romaji ("ōkē") spells the English answer, so it waits until you answer.
                        if let sub = shown.sub, !moment.entry.loanword || picked != nil { Text(sub).font(.headline).foregroundStyle(.white) }
                        Text(shown.main).font(.system(size: wordSize * 0.9, weight: .heavy, design: .rounded)).foregroundStyle(accent)
                    }
                    Spacer()
                    Button { Speech.shared.say(moment.entry.mainKana) } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.title3)
                            .foregroundStyle(.black).frame(width: 44, height: 44)
                            .background(accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hear \(moment.entry.kana)")
                }
                Text(isReview ? "Quick review from an earlier Short. What does it mean?" : "You met this in an earlier Short. Here it is in a new one. What does it mean?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            ForEach(options) { o in optionButton(o) }
        }
    }

    private func optionButton(_ o: VocabEntry) -> some View {
                Button {
                    guard picked == nil else { return }
                    picked = o.id
                    let ok = o.id == moment.entry.id
                    session.answerRecall(correct: ok, seconds: Date().timeIntervalSince(askedAt))
                    SoundFX.answer(correct: ok)
                    // Let the ✓/✗ register before the reveal replaces the options.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 650))
                        revealed = true
                    }
                } label: {
                    HStack {
                        optionLabel(o)
                        if let mark = optionMark(o) {
                            Image(systemName: mark.symbol)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(mark.color)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 52)
                    .background(optionBackground(o), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(optionMark(o)?.color ?? .clear, lineWidth: 2)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(picked != nil)
                .animation(.snappy, value: picked)
                .accessibilityIdentifier("recall-option")
    }

    /// Spell / say cards: record the answer, then reveal like a multiple-choice card.
    private func answer(correct: Bool) {
        guard picked == nil else { return }
        speech.stop()
        picked = correct ? moment.entry.id : "missed"
        session.answerRecall(correct: correct, seconds: Date().timeIntervalSince(askedAt) / 2.5)   // building takes longer than tapping
        SoundFX.answer(correct: correct)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 650))
            revealed = true
        }
    }

    /// Review by ear: the word is played, nothing is written, pick the meaning.
    private var hearItPrompt: some View {
        HStack(spacing: 14) {
            Button { Speech.shared.say(moment.entry.mainKana) } label: {
                Image(systemName: "ear.fill").font(.title).foregroundStyle(.black)
                    .frame(width: 64, height: 64).background(accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Play the word again")
            .accessibilityIdentifier("replay")
            Text("What does it mean?").font(.headline).foregroundStyle(.white)
        }
    }

    /// Review by spelling: build the word from kana tiles. Romaji stays under the tiles for kana beginners.
    private func spellQuestion(tiles: [String], answer target: [String]) -> some View {
        let romaji = session.settings.scriptLevel.rawValue <= ScriptLevel.kanaRomaji.rawValue
        return VStack(alignment: .leading, spacing: 10) {
            (Text("Spell ") + Text("\"\(session.vocab.shortMeaning(moment.entry))\"").foregroundStyle(accent).bold() + Text(" in kana"))
                .font(.headline).foregroundStyle(.white)
            // Several Japanese words mean this (やさしい, かんたん…): say which one the tiles are for.
            if let hint = session.vocab.whichWordHint(for: moment.entry) {
                Text(hint).font(.subheadline).foregroundStyle(.white).accessibilityIdentifier("spell-hint")
            }
            FlowTiles(items: placed.map { tiles[$0] }, style: .placed, placeholder: placed.count < target.count, romaji: romaji) { i in
                if picked == nil { placed.remove(at: i) }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(10)
            .background(panelBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            FlowTiles(items: tiles, style: .bank, used: Set(placed), romaji: romaji) { i in
                guard picked == nil, !placed.contains(i), placed.count < target.count else { return }
                placed.append(i)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            HStack {
                Button { answer(correct: false) } label: {
                    Label("I don't know", systemImage: "eye.fill").labelStyle(.iconOnly).font(.title3)
                        .frame(width: 44, height: 44)
                }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Button { answer(correct: placed.map { tiles[$0] } == target) } label: {
                    Text("Check").font(.headline).foregroundStyle(.black)
                        .padding(.horizontal, 22).frame(height: 44)
                        .background(accent, in: Capsule())
                }
                .disabled(placed.count < target.count)
                .opacity(placed.count < target.count ? 0.4 : 1)
                .accessibilityIdentifier("spell-check")
            }
            .buttonStyle(.plain)
        }
    }

    /// Review out loud: say the Japanese for the meaning; speech recognition checks it.
    private var sayQuestion: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("Say ") + Text("\"\(session.vocab.shortMeaning(moment.entry))\"").foregroundStyle(accent).bold() + Text(" in Japanese"))
                .font(.headline).foregroundStyle(.white)
            HStack(spacing: 14) {
                Button {
                    if speech.state == .listening { speech.stop() } else { Task { await speech.start(target: moment.entry.mainKana, alternatives: session.vocab.equivalents(of: moment.entry).map(\.mainKana)) } }
                } label: {
                    Image(systemName: speech.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.title).foregroundStyle(.black)
                        .frame(width: 64, height: 64).background(accent, in: Circle())
                        .scaleEffect(1 + CGFloat(speech.level) * 0.15)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(speech.state == .listening ? "Stop listening" : "Start speaking")
                .accessibilityIdentifier("say-mic")
                VStack(alignment: .leading, spacing: 2) {
                    switch speech.state {
                    case .idle: EmptyView()
                    case .listening: Image(systemName: "waveform").foregroundStyle(accent).symbolEffect(.variableColor.iterative)
                    case .heard(let t, let ok):
                        Label("「\(t)」", systemImage: ok ? "checkmark.circle.fill" : "arrow.clockwise")
                            .foregroundStyle(ok ? Brand.OnDark.right : .white)
                        if ok, let alt = speech.heardAlternative {
                            // Another right word for the same meaning: right, and here's this card's word.
                            Text("\(alt) is right too · this card's word is \(moment.entry.mainKana)")
                                .font(.subheadline).foregroundStyle(.white)
                                .accessibilityIdentifier("say-alternative")
                        }
                    case .denied, .unavailable:
                        Image(systemName: "mic.slash.fill").foregroundStyle(.white)
                            .accessibilityLabel("Speech recognition isn't available")
                    }
                }
                .font(.headline)
            }
            HStack {
                Button { speech.stop(); session.finishMoment() } label: {
                    Label("Can't talk now", systemImage: "speaker.slash.fill").labelStyle(.iconOnly).font(.title3)
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Button { answer(correct: false) } label: {
                    Label("Show answer", systemImage: "eye.fill").labelStyle(.iconOnly).font(.title3)
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(accent)
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .buttonStyle(.plain)
        }
    }

    /// Listen: no text before answering, a big replay button instead.
    private func listenPrompt(kanaDrill: Bool) -> some View {
        HStack(spacing: 14) {
            Button {
                Speech.shared.say(moment.entry.mainKana)
            } label: {
                Image(systemName: "ear.fill")
                    .font(.title)
                    .foregroundStyle(.black)
                    .symbolEffect(.bounce, options: .repeat(2), value: picked == nil)
                    .frame(width: 64, height: 64)
                    .background(accent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Play the sound again")
            .accessibilityIdentifier("replay")
            VStack(alignment: .leading, spacing: 2) {
                Text("Which sound did you hear?")
                    .font(.headline).foregroundStyle(.white)
                Text("Tap the ear to hear it again.")
                    .font(.subheadline).foregroundStyle(.white)
            }
        }
    }

    /// Picture: the Short's own frame (thing outlined when Jev located it reliably) + the question.
    @ViewBuilder
    private func pictureQuestion(ask: PictureAsk, frame: UIImage?, box: CGRect?) -> some View {
        if let frame { framePreview(frame, box: box) }
        switch ask {
        case .whatsThis:
            Text(box == nil ? "What's in this Short? Say it in Japanese." : "What's the outlined thing in Japanese?")
                .font(.headline).foregroundStyle(.white)
        case .whichOne:
            Text("What's the outlined thing?")
                .font(.headline).foregroundStyle(.white)
        case .color(let thing):
            (Text("What color is the ") + Text(thing.kana).foregroundStyle(accent).bold()
             + Text(" (\(thing.meaning))?"))
                .font(.headline).foregroundStyle(.white)
        }
    }

    private func framePreview(_ image: UIImage, box: CGRect?) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                if let box {
                    GeometryReader { g in
                        let r = CGRect(x: box.minX * g.size.width, y: box.minY * g.size.height,
                                       width: box.width * g.size.width, height: box.height * g.size.height)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(accent, lineWidth: 3)
                            .shadow(color: .black.opacity(0.6), radius: 3)
                            .frame(width: max(r.width, 24), height: max(r.height, 24))
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: 190)
            .accessibilityLabel(box == nil ? "Screenshot from this Short" : "Screenshot from this Short, with one thing outlined")
    }

    /// After answering: ✓ on the right option, ✗ on a wrong pick.
    private func optionMark(_ o: VocabEntry) -> (symbol: String, color: Color)? {
        guard let picked else { return nil }
        if o.id == moment.entry.id { return ("checkmark.circle.fill", Brand.OnDark.right) }
        if o.id == picked { return ("xmark.circle.fill", Brand.OnDark.wrong) }
        return nil
    }

    private func optionBackground(_ o: VocabEntry) -> Color {
        guard picked != nil else { return panelBG }
        if o.id == moment.entry.id { return Brand.OnDark.right.opacity(0.28) }
        if o.id == picked { return Brand.OnDark.wrong.opacity(0.28) }
        return panelBG.opacity(0.5)
    }

    /// Recall: English meaning (no emoji, it would give it away).
    /// Listen: the kana (sound drill).
    /// Picture / review-to-Japanese: Japanese only (that's what's being asked).
    @ViewBuilder
    private func optionLabel(_ o: VocabEntry) -> some View {
        let shown = level.display(o)
        switch moment.kind {
        case .listen:
            HStack(spacing: 10) {
                Text(o.kana).font(.title.weight(.heavy)).foregroundStyle(accent)
                Spacer()
            }
        case .picture, .review(_, true, _), .recall(_, true):
            HStack(spacing: 10) {
                Text(shown.main).font(.title3.weight(.heavy)).foregroundStyle(accent)
                if let sub = shown.sub { Text(sub).font(.subheadline).foregroundStyle(.white) }
                Spacer()
            }
        default:
            HStack {
                Text(session.vocab.shortMeaning(o)).font(.headline)
                Spacer()
            }
        }
    }

    /// When this word comes back, from the review schedule ("in 3 days · Tue").
    private var nextCheck: String {
        guard let due = session.wordBook.progress(moment.entry.id)?.due else { return "soon" }
        let secs = due.timeIntervalSinceNow
        if secs < 60 * 60 { return "in a few minutes" }
        if secs < 20 * 3600 { return "in \(Int((secs / 3600).rounded())) h" }
        let days = Int((secs / 86400).rounded())
        return "in \(days) day\(days == 1 ? "" : "s") · \(due.formatted(.dateTime.weekday(.abbreviated)))"
    }

    private var recallResult: some View {
        let ok = picked == moment.entry.id
        let text: String
        switch moment.kind {
        case .listen:
            text = ok ? "Good ear! That's \(moment.entry.kana) (\(moment.entry.romaji))." : "That was \(moment.entry.kana) (\(moment.entry.romaji)). Listen once more."
        case .picture(_, .color(let thing), _, _, _):
            text = ok ? "Yes, the \(thing.kana) is \(moment.entry.kana)!" : "The \(thing.kana) is \(moment.entry.kana) (\(session.vocab.shortMeaning(moment.entry)))."
        case .picture(_, .whichOne, _, _, _):
            text = ok ? "Yes! There's a \(moment.entry.kana) in it." : "The picture has \(moment.entry.kana) (\(session.vocab.shortMeaning(moment.entry))) in it."
        case .picture:
            text = ok ? "Correct! That's \(moment.entry.kana)." : "The outlined thing is the \(moment.entry.emoji) \(session.vocab.shortMeaning(moment.entry)): \(moment.entry.kana) (\(moment.entry.romaji))."
        case .review, .hearIt, .spell, .say:
            text = ok ? "You remembered! Next check \(nextCheck)." : "It's \(moment.entry.kana) (\(moment.entry.romaji)). Next check \(nextCheck)."
        default:
            text = ok ? "Correct! Next check \(nextCheck)." : "Not quite. Next check \(nextCheck)."
        }
        return Label(text,
                     systemImage: ok ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(ok ? Brand.OnDark.right : Brand.OnDark.peach)
    }

    // MARK: Reveal

    private var reveal: some View {
        VStack(alignment: .leading, spacing: 12) {
            if picked != nil { recallResult }

            // Meaning
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("", symbol: "character.book.closed")
                HStack(alignment: .firstTextBaseline) {
                    Text(session.vocab.shortMeaning(moment.entry))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(moment.entry.written)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                if !moment.entry.otherKana.isEmpty {
                    Text("also read: \(moment.entry.otherKana.joined(separator: ", "))")
                        .font(.subheadline).foregroundStyle(.white)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let tip = Insights.tip(for: moment.entry) {
                // Learn-as-you-go insight about this kind of word, one line.
                Label(tip, systemImage: "lightbulb.fill")
                    .font(.subheadline).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("word-tip")
            }

            readingRow

            if session.settings.showJapaneseSentence, let ja = moment.japaneseLine {
                japaneseSection(ja)
            }
        }
    }

    /// How to read it: each kana with its sound. Tap a tile to hear it. Collapsed by default.
    private var readingRow: some View {
        let units = Kana.units(moment.entry.kana)
        // One note per kind (オーケー has two ー but needs the long-mark tip once).
        let notes = units.compactMap(\.note).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return ExpandableSection(
            title: Kana.isKatakana(moment.entry.kana) ? "Katakana" : "Hiragana",
            symbol: "textformat.abc",
            summary: units.map(\.kana).joined(separator: "·") + " = " + moment.entry.romaji,
            isOpen: $readingOpen,
            background: panelBG,
            id: "toggle-reading"
        ) {
            // Wraps instead of scrolling sideways, and the full romaji sits on its own line, so it's never cut off.
            WrapLayout(spacing: 8) {
                    ForEach(Array(units.enumerated()), id: \.offset) { _, u in
                        Button { Speech.shared.say(u.kana) } label: {
                            VStack(spacing: 2) {
                                Text(u.kana).font(.title.weight(.bold)).foregroundStyle(.white)
                                Text(u.romaji).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                            }
                            .frame(minWidth: 52, minHeight: 64)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
            }
            Text("= \(moment.entry.romaji)")
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { n in
                Text(n).font(.subheadline).foregroundStyle(.white)
            }
        }
    }

    /// The same line in Japanese (example sentence). Collapsed by default.
    /// The video's Japanese line only when it actually contains the word; otherwise a reliable short example instead
    /// (machine translations that drop the word, or add clauses, make a misleading pair for beginners).
    private func japaneseSection(_ ja: String) -> AnyView {
        if VocabStore.range(of: moment.entry, inJapanese: ja) == nil {
            guard let ex = SimpleExample.make(for: moment.entry) else { return AnyView(EmptyView()) }
            return AnyView(ExpandableSection(
                title: "Example",
                symbol: "text.bubble.fill",
                summary: ex.ja,
                isOpen: $exampleOpen,
                background: panelBG,
                id: "toggle-example"
            ) {
                Text(ex.ja).font(.title3).foregroundStyle(.white)
                Text("\(ex.romaji) · \(ex.en)").font(.subheadline).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button { Speech.shared.say(ex.ja) } label: {
                        Label("Listen", systemImage: "play.circle.fill")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.black)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Listen to the example")
                }
            }
            .accessibilityIdentifier("simple-example"))
        }
        return AnyView(ExpandableSection(
            title: "In Japanese",
            symbol: "globe.asia.australia.fill",
            summary: ja,
            isOpen: $exampleOpen,
            background: panelBG,
            id: "toggle-example"
        ) {
            Text(highlightedJapanese(ja))
                .font(.title3)
                .foregroundStyle(.white)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !moment.line.isEmpty {
                Text("English: “\(moment.line)”").font(.subheadline).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let found = VocabStore.range(of: moment.entry, inJapanese: ja) != nil
            if !found, let ex = SimpleExample.make(for: moment.entry) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Example").font(.caption2.weight(.bold)).foregroundStyle(accent)
                    Text(ex.ja).font(.headline).foregroundStyle(.white)
                    Text("\(ex.romaji) · \(ex.en)").font(.subheadline).foregroundStyle(.white)
                }
                .onTapGesture { Speech.shared.say(ex.ja) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("simple-example")
            }
            HStack(alignment: .center) {
                Spacer(minLength: 8)
                Button { session.hearJapaneseLine() } label: {
                    Label("Listen", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Listen to the Japanese line")
            }
        })
    }

    // MARK: Actions

    private var actions: some View {
      VStack(spacing: 6) {
        HStack(spacing: 12) {
            if revealed {
                if !isRecall {
                    Button { session.finishMoment(known: true) } label: {
                        Text("I knew it")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(Capsule())
                            .glass(in: Capsule(), interactive: true)
                            .foregroundStyle(.white)
                    }
                }
                Button { session.finishMoment() } label: {
                    Label("Continue", systemImage: "play.fill")
                        .accessibilityIdentifier("continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Capsule())
                        .glass(in: Capsule(), tint: accent.opacity(0.9), interactive: true)
                        .foregroundStyle(.black)
                }
            }
        }
        .buttonStyle(.plain)

      }
    }

    private func highlightedJapanese(_ ja: String) -> AttributedString {
        var s = AttributedString(ja)
        if let r = VocabStore.range(of: moment.entry, inJapanese: ja),
           let lower = AttributedString.Index(r.lowerBound, within: s),
           let upper = AttributedString.Index(r.upperBound, within: s) {
            s[lower..<upper].foregroundColor = accent
            s[lower..<upper].font = .title3.weight(.heavy)
            s[lower..<upper].underlineStyle = .single
        }
        return s
    }
}

/// A section that shows a one-line preview and expands on tap (toggle list).
struct ExpandableSection<Content: View>: View {
    let title: String
    let symbol: String
    let summary: String
    @Binding var isOpen: Bool
    let background: Color
    let id: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { isOpen.toggle() }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Label(title, systemImage: symbol)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    if !isOpen {
                        Text(summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)   // "た·い·せ·つ = taisetsu" must not lose its last letters
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
            .accessibilityValue(isOpen ? "expanded" : "collapsed")

            if isOpen {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Slight press-down for custom buttons (system buttons do this for free).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The analyzed frame laid back over the video at full size, with the outline on the real object.
/// Uses global (window) coordinates, the same space the frame was captured in.
struct FrameOverlay: View {
    let image: UIImage
    let rect: CGRect
    let box: CGRect?
    let accent: Color
    var showBox = true
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let origin = g.frame(in: .global).origin
            let local = rect.offsetBy(dx: -origin.x, dy: -origin.y)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: local.width, height: local.height)
                if let box, showBox {
                    let r = CGRect(x: box.minX * local.width, y: box.minY * local.height,
                                   width: max(box.width * local.width, 28), height: max(box.height * local.height, 28))
                    // Dim everything except the outlined thing, then outline it.
                    Rectangle()
                        .fill(.black.opacity(0.35))
                        .reverseMask { RoundedRectangle(cornerRadius: 12).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY) }
                        .frame(width: local.width, height: local.height)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent, lineWidth: 4)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                        .frame(width: r.width, height: r.height)
                        .scaleEffect(pulse ? 1.04 : 1)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .frame(width: local.width, height: local.height)
            .offset(x: local.minX, y: local.minY)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private extension View {
    /// Cuts the given shape out of this view.
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask {
            Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup()
        }
    }
}
