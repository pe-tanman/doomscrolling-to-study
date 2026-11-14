import SwiftUI

/// One practice item for one phrase and one skill. Fills that skill's coverage dot when done right.
/// Reading: read the line, pick the meaning. Listening: hear it (no text), pick the meaning.
/// Writing: build it from tiles. Speaking: say it (on-device speech recognition).
struct PhrasePractice: View {
    let phrase: Phrase
    let skill: Skill
    let place: Place
    /// The answer was just revealed (an earlier mistake on this phrase): practice, but no dot.
    var guided = false
    /// The answer comes back at the end of this set if missed (shown in the result).
    var retryLater = true
    /// Called with whether it was right; the caller moves on.
    var onDone: (Bool) -> Void

    @State private var picked: String?
    @State private var placed: [Int] = []
    /// Building is only judged when the learner taps Check (a slipped tap can be undone first).
    @State private var checked = false
    @State private var tiles: [String] = []
    @State private var options: [String] = []
    @StateObject private var speech = SpeechCheck()
    @State private var started = Date()

    private var correct: Bool? {
        switch skill {
        case .reading, .listening: return picked.map { $0 == phrase.exampleEnglish }
        case .writing: return checked && placed.count == phrase.tiles.count ? placed.map { tiles[$0] } == phrase.tiles : nil
        case .speaking: if case .heard(_, let ok) = speech.state, ok { return true } else { return nil }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                SkillChip(skill: skill)
                // Listening and writing would be given away by the phrase in the header.
                Label(place.name, systemImage: "mappin.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep).lineLimit(1)
                if guided {
                    Image(systemName: "hand.point.up.left.fill").font(.subheadline).foregroundStyle(Brand.warn)
                        .padding(6).background(Brand.warn.opacity(0.15), in: Circle())
                        .accessibilityLabel("Guided practice: a recall check comes at the end of the set")
                        .accessibilityIdentifier("guided-chip")
                }
            }
            switch skill {
            case .reading: reading
            case .listening: listening
            case .writing: writing
            case .speaking: speaking
            }
            if let ok = correct { result(ok) }
        }
        .answerEffects()
        .onAppear(perform: setup)
        .onDisappear { speech.stop() }
    }

    // MARK: Modes

    private var reading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What does it mean?").font(.headline).foregroundStyle(Brand.ink)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    japaneseLine(phrase.example)
                    // Pronunciation help for kana beginners; hidden in the end-of-set recall check (no hints there).
                    if retryLater || picked != nil {
                        Text(phrase.romaji).font(.callout).foregroundStyle(Brand.violetDeep)
                    }
                }
                Spacer()
                hearButton
            }
            choices
        }
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button { Speech.shared.say(phrase.exampleKana) } label: {
                    Image(systemName: "ear.fill").font(.title).foregroundStyle(.white)
                        .frame(width: 64, height: 64).background(Brand.violet, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play again")
                VStack(alignment: .leading, spacing: 2) {
                    Text("What did you hear?").font(.headline).foregroundStyle(Brand.ink)
                    Button { Speech.shared.saySlowly(phrase.exampleKana) } label: {
                        Label("Slowly", systemImage: "tortoise.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hear-slowly")
                }
            }
            if picked != nil {
                // Same support as the reading screen: the line, its romaji and a replay.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        japaneseLine(phrase.example)
                        Text(phrase.romaji).font(.callout).foregroundStyle(Brand.violetDeep)
                    }
                    Spacer()
                    hearButton
                }
            }
            choices
        }
        .onAppear { Speech.shared.say(phrase.exampleKana) }
    }

    private var writing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Build: \"\(phrase.exampleEnglish)\"").font(.headline).foregroundStyle(Brand.ink)
            FlowTiles(items: placed.map { tiles[$0] }, style: .placed, placeholder: placed.count < phrase.tiles.count) { i in
                if correct == nil { placed.remove(at: i) }   // tap a placed tile to take it back
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(12)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            // Used tiles stay in place (dimmed), so the tray never reflows under a quick finger.
            FlowTiles(items: tiles, style: .bank, used: Set(placed)) { i in
                guard correct == nil, !placed.contains(i), placed.count < phrase.tiles.count else { return }
                placed.append(i)
            }
            if correct == nil {
                HStack {
                    Image(systemName: "hand.tap.fill").font(.title3).foregroundStyle(Brand.violetDeep)
                        .accessibilityLabel("Tap tiles in order. Tap a placed tile to take it back.")
                    Spacer()
                    Button("Check") { checked = true; finishCheck() }
                        .buttonStyle(.brandPrimary)
                        .frame(maxWidth: 140)
                        .disabled(placed.count < phrase.tiles.count)
                        .opacity(placed.count < phrase.tiles.count ? 0.4 : 1)
                        .accessibilityIdentifier("build-check")
                }
            }
        }
    }

    private var speaking: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Say it out loud").font(.headline).foregroundStyle(Brand.ink)
            HStack {
                japaneseLine(phrase.example)
                Spacer()
                hearButton.accessibilityLabel("Hear it first")
            }
            Text("\(phrase.exampleEnglish)  ·  \(phrase.romaji)")
                .font(.subheadline).foregroundStyle(Brand.violetDeep)
            if let u = phrase.usage { usageNote(u) }
            HStack(spacing: 14) {
                Button {
                    if speech.state == .listening { speech.stop() } else { Task { await speech.start(target: phrase.exampleKana) } }
                } label: {
                    Image(systemName: speech.state == .listening ? "stop.fill" : "mic.fill")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Skill.speaking.color, in: Circle())
                        .scaleEffect(1 + CGFloat(speech.level) * 0.15)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.state == .listening ? "Stop listening" : "Start speaking")
                VStack(alignment: .leading, spacing: 2) {
                    switch speech.state {
                    case .idle: EmptyView()
                    case .listening: Image(systemName: "waveform").foregroundStyle(Skill.speaking.color).symbolEffect(.variableColor.iterative)
                    case .heard(let t, let ok): Text("「\(t)」").font(Brand.jp(17)).foregroundStyle(ok ? Brand.success : Brand.ink)
                        if !ok { Image(systemName: "arrow.clockwise").foregroundStyle(Brand.ink).accessibilityLabel("Almost, try once more") }
                    case .denied, .unavailable: Image(systemName: "mic.slash.fill").foregroundStyle(Brand.ink)
                        .accessibilityLabel("Speech recognition isn't available. Allow the microphone in iPhone Settings")
                    }
                }
                .font(.headline)
            }
            if speech.state == .denied || speech.state == .unavailable {
                Button { onDone(false) } label: { Label("Skip speaking", systemImage: "speaker.slash.fill") }.buttonStyle(.brandQuiet)
            }
        }
        .onChange(of: speech.state) { _, s in if case .heard(_, true) = s { SoundFX.answer(correct: true) } }
    }

    // MARK: Pieces

    private var hearButton: some View {
        Button { Speech.shared.say(phrase.exampleKana) } label: {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(Brand.violetDeep)
                .frame(width: 44, height: 44).background(Brand.violetSoft, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Hear it")
    }

    /// When to say it: a tiny real-life scene.
    private func usageNote(_ u: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(Skill.speaking.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(u).font(.subheadline).foregroundStyle(Brand.ink)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Skill.speaking.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("usage-note")
    }

    private func japaneseLine(_ s: String) -> some View {
        // Word joiners inside each word, so lines break only at spaces ("いきませんか？" never splits).
        Text(s.split(separator: " ", omittingEmptySubsequences: false).map { $0.map(String.init).joined(separator: "\u{2060}") }.joined(separator: " ")).font(Brand.jp(26, bold: true, relativeTo: .title2)).foregroundStyle(Brand.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var choices: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { o in
                Button {
                    guard picked == nil else { return }
                    picked = o
                    SoundFX.answer(correct: o == phrase.exampleEnglish)
                } label: {
                    HStack {
                        Text(o).font(.headline).foregroundStyle(Brand.ink)
                        Spacer()
                        if let picked, o == phrase.exampleEnglish { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success) }
                        else if picked == o { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.danger) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(bg(o), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked != nil && o == phrase.exampleEnglish ? Brand.success : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice-option")
            }
        }
    }

    private func bg(_ o: String) -> Color {
        guard let picked else { return Brand.mist }
        if o == phrase.exampleEnglish { return Brand.successSoft }
        return o == picked ? Color.red.opacity(0.12) : Brand.mist
    }

    private func result(_ ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ok ? (guided ? "Good practice" : "\(skill.title) ✓") : (retryLater ? "Again at the end" : "Still a gap"),
                  systemImage: ok ? "checkmark.seal.fill" : "arrow.uturn.backward.circle.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(ok ? Brand.success : Brand.warn)
            if skill != .speaking, let u = phrase.usage { usageNote(u) }
            Button("Continue") { onDone(ok) }   // no replay here: it would play after the card is gone
            .buttonStyle(.brandPrimary)
            .accessibilityIdentifier("practice-continue")
        }
    }

    private func finishCheck() {
        SoundFX.answer(correct: correct == true)
    }

    private func setup() {
        started = Date()
        // Wrong choices from the same place (all shop phrases in Konbini), so a guess isn't eliminated by topic.
        let samePlace = place.phrases.filter { $0.id != phrase.id }.map(\.exampleEnglish)
        let others = (samePlace.count >= 2 ? samePlace : samePlace + Curriculum.allPhrases.filter { $0.id != phrase.id }.map(\.exampleEnglish))
        options = ([phrase.exampleEnglish] + Array(NSOrderedSet(array: others).array.compactMap { $0 as? String }.filter { $0 != phrase.exampleEnglish }.shuffled().prefix(2))).shuffled()
        // Wrong tiles from the same place's phrases (どこ, いきますか…), not random fragments from elsewhere.
        let samePlaceTiles = place.phrases.filter { $0.id != phrase.id }.flatMap(\.tiles)
        let pool = samePlaceTiles.filter { !phrase.tiles.contains($0) && $0.count > 1 }
        let extra = (pool.count >= 2 ? pool : pool + Curriculum.allPhrases.filter { $0.id != phrase.id }.flatMap(\.tiles).filter { !phrase.tiles.contains($0) })
            .shuffled().prefix(2)
        tiles = (phrase.tiles + extra).shuffled()
        placed = []
        checked = false
        picked = nil
    }
}

/// Wrapping row of Japanese tiles. Empty strings render as used slots.
struct FlowTiles: View {
    enum Style { case placed, bank }
    let items: [String]
    var style: Style
    var placeholder = false
    var used: Set<Int> = []
    /// Romaji under each tile (off when the sound itself is what's being tested).
    var romaji = true
    var tap: (Int) -> Void

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                Button { tap(i) } label: {
                    VStack(spacing: 1) {
                        Text(t.isEmpty ? "　　" : t)
                            .font(Brand.jp(18))
                            .foregroundStyle(t.isEmpty ? .clear : Brand.ink)
                        // Romaji under each tile, so the build step has the same support as reading.
                        if romaji {
                            Text(t.isEmpty ? " " : Romanize.pronounced(t))
                                .font(.caption.weight(.semibold)).foregroundStyle(t.isEmpty ? .clear : Brand.violetDeep)
                        }
                    }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(t.isEmpty ? Brand.mist : (style == .placed ? Brand.violetSoft : Brand.surface),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style == .placed ? Brand.violet : Brand.line, lineWidth: style == .placed ? 2 : 1.5))
                }
                .buttonStyle(.plain)
                .disabled(t.isEmpty || used.contains(i))
                .opacity(used.contains(i) ? 0.25 : 1)
                .accessibilityIdentifier(style == .bank ? "tile" : "placed-tile")
            }
            if placeholder {
                Text("？").font(Brand.jp(18)).foregroundStyle(Brand.ink3)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
        }
    }
}

/// Simple wrapping layout.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // No width offered (e.g. inside ViewThatFits): size to the screen, never wider, so rows wrap instead of clipping.
        let w = min(proposal.width ?? (UIScreen.main.bounds.width - 64), UIScreen.main.bounds.width - 32)
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

/// A run of practice items (gaps of a place, a skill, or a can-do), with progress and close.
struct PracticeQueue: View {
    struct Item { let phrase: Phrase; let skill: Skill; var isRetry = false }
    let place: Place
    @ObservedObject var journey: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var started = Date()
    @State private var items: [Item]
    /// Phrases whose answer was revealed by a mistake in this set.
    @State private var revealed: Set<String> = []
    /// "phraseId|skill" dots actually filled in this set.
    @State private var filled: Set<String> = []

    /// Quick sets promise a fixed number of steps: no retries appended (misses stay as gaps instead).
    var allowRetries = true

    init(items: [(phrase: Phrase, skill: Skill)], place: Place, journey: JourneyStore, allowRetries: Bool = true) {
        self.place = place
        self.journey = journey
        self.allowRetries = allowRetries
        // Listening first (before reading reveals the meaning), then reading, writing, speaking; across phrases this
        // spaces one phrase's tasks apart instead of answering them back to back.
        let rank: [Skill: Int] = [.listening: 0, .reading: 1, .writing: 2, .speaking: 3]
        let ordered = items.enumerated().sorted { a, b in
            let ra = rank[a.element.skill] ?? 9, rb = rank[b.element.skill] ?? 9
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        _items = State(initialValue: ordered.map { Item(phrase: $0.phrase, skill: $0.skill) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button { finish() } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                        .frame(width: 36, height: 36).background(Brand.surface, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
                HStack(spacing: 6) {
                    ForEach(0..<max(1, items.count), id: \.self) { i in
                        Capsule().fill(i <= index ? Brand.violet : Brand.line).frame(height: 8)
                    }
                }
            }
            if index < items.count {
                let it = items[index]
                let guided = !it.isRetry && revealed.contains(it.phrase.id)
                ScrollView {
                    PhrasePractice(phrase: it.phrase, skill: it.skill, place: place, guided: guided, retryLater: !it.isRetry) { ok in
                        if ok && !guided { journey.mark(it.phrase.id, it.skill); filled.insert("\(it.phrase.id)|\(it.skill.rawValue)") }
                        if !ok && it.skill == .speaking && SpeechCheck.permissionDenied {
                            // Mic / speech recognition unavailable: one Skip skips every speaking step in this set
                            // (they stay as gaps), instead of repeating the same permission screen.
                            let rest = items[(index + 1)...].filter { $0.skill != .speaking }
                            items = Array(items[...index]) + rest
                            withAnimation { index += 1 }
                            return
                        }
                        if !ok { revealed.insert(it.phrase.id) }
                        // Misses and guided wins come back once at the end with the answer hidden.
                        if allowRetries, (!ok || guided) && !it.isRetry { items.append(Item(phrase: it.phrase, skill: it.skill, isRetry: true)) }
                        withAnimation { index += 1 }
                    }
                    .id(index)
                    .brandCard()
                }
            } else {
                Spacer()
                VStack(spacing: 12) {
                    MascotImage(mood: .cheer, size: 140)
                    // Finished the set ≠ filled every dot: say what's still open (skipped or missed).
                    let all = Set(items.map { "\($0.phrase.id)|\($0.skill.rawValue)" })
                    let open = all.subtracting(filled)
                    let openSkills = Dictionary(grouping: open, by: { $0.split(separator: "|").last.map(String.init) ?? "" })
                        .compactMap { k, v in Skill(rawValue: k).map { "\(v.count) \($0.title.lowercased())" } }.sorted()
                    Text(items.isEmpty ? "Nothing missing here!" : open.isEmpty ? "All done!" : "Set finished").font(.title2.weight(.bold)).fontDesign(.rounded)
                    if !open.isEmpty {
                        HStack(spacing: 14) {
                            Label("\(filled.count)", systemImage: "circle.fill").foregroundStyle(Brand.success)
                            Label("\(open.count)", systemImage: "circle.dotted").foregroundStyle(Brand.warn)
                        }
                        .font(.title3.weight(.bold))
                        .accessibilityLabel("\(filled.count) dots filled, still open: \(openSkills.joined(separator: ", "))")
                            .accessibilityIdentifier("set-open-summary")
                    }
                    Button { finish() } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(.brandPrimary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
        .background(Brand.sky.ignoresSafeArea())
        .onAppear { started = Date() }
    }

    private func finish() {
        journey.addPracticeTime(Date().timeIntervalSince(started))
        dismiss()
    }
}
