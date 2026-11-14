import SwiftUI

/// A chunk / pattern question over the paused Short: the line just heard, with one grammar piece to fill in.
/// - notice (first meeting): the piece is highlighted and explained, then a guided pick (no proof of recall yet);
/// - cloze: fill the blank from 2–3 options (Jev made sure only one is right);
/// - build: put the chunk (word + piece + next word) in order, with one wrong tile in the bank.
struct GrammarCardView: View {
    let moment: GrammarMoment
    @ObservedObject var session: FeedSession

    @State private var introDone = false
    @State private var picked: String?
    @State private var placed: [Int] = []
    @State private var checked = false

    private var guided: Bool { moment.mode == .notice }
    private var asking: Bool { moment.mode != .notice || introDone }

    private var correct: Bool? {
        switch moment.mode {
        case .notice, .cloze: return picked.map { $0 == moment.piece }
        case .build: return checked ? placed.map { moment.bank[$0] } == moment.chunk : nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack {
                HStack {
                    LadderChip(stage: session.ladderStage, point: moment.point)
                    Spacer()
                    Button { session.skipGrammar() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip")
                    .accessibilityIdentifier("grammar-skip")
                }
                .padding(.horizontal, 16).padding(.top, 58)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                // The English line from the Short: it's what makes the right piece clear.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening").foregroundStyle(Brand.violet)
                    Text(moment.en).font(.headline).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
                }
                if asking { question } else { intro }
                if let ok = correct { result(ok) }
            }
            .brandCard(Brand.surface.opacity(0.97))
            .answerEffects()
            .environment(\.colorScheme, .light)
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("grammar-card")
        .onAppear { SoundFX.play(.pop) }
    }

    // MARK: Notice

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New pattern in this line").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
            lineView(highlight: true)
            wordChips
            tipBox
            Button { withAnimation(.snappy) { introDone = true } } label: {
                Label("Try it", systemImage: "hand.point.up.left.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.brandPrimary)
            .accessibilityIdentifier("grammar-try")
        }
    }

    // MARK: Question

    @ViewBuilder private var question: some View {
        switch moment.mode {
        case .notice, .cloze:
            VStack(alignment: .leading, spacing: 12) {
                Text("Fill the gap").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                lineView(highlight: picked != nil)
                wordChips
                HStack(spacing: 10) {
                    ForEach(moment.options, id: \.self) { o in optionButton(o) }
                }
            }
        case .build:
            VStack(alignment: .leading, spacing: 12) {
                Text("Build the chunk").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                if checked { lineView(highlight: true) } else { wordChips }
                FlowTiles(items: placed.map { moment.bank[$0] }, style: .placed, placeholder: placed.count < moment.chunk.count) { i in
                    if correct == nil { placed.remove(at: i) }
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .padding(12)
                .background(Brand.mist, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                FlowTiles(items: moment.bank, style: .bank, used: Set(placed)) { i in
                    guard correct == nil, !placed.contains(i), placed.count < moment.chunk.count else { return }
                    placed.append(i)
                }
                if correct == nil {
                    Button("Check") {
                        checked = true
                        SoundFX.answer(correct: correct == true)
                        Speech.shared.say(moment.ja)
                    }
                    .buttonStyle(.brandPrimary)
                    .disabled(placed.count < moment.chunk.count)
                    .opacity(placed.count < moment.chunk.count ? 0.4 : 1)
                    .accessibilityIdentifier("grammar-check")
                }
            }
        }
    }

    private func optionButton(_ o: String) -> some View {
        let isAnswer = o == moment.piece
        let bg: Color = picked == nil ? Brand.mist : isAnswer ? Brand.successSoft : (o == picked ? Brand.dangerSoft : Brand.mist)
        return Button {
            guard picked == nil else { return }
            picked = o
            SoundFX.answer(correct: isAnswer)
            Speech.shared.say(moment.ja)
        } label: {
            VStack(spacing: 2) {
                Text(o).font(Brand.jp(22, bold: true)).foregroundStyle(Brand.ink)
                Text(Romanize.pronounced(o)).font(.caption.weight(.semibold)).foregroundStyle(Brand.violetDeep)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(picked != nil && isAnswer ? Brand.success : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(o), \(Romanize.pronounced(o))")
        .accessibilityIdentifier("grammar-option")
    }

    // MARK: Pieces

    /// The Short's Japanese line. The piece is a blank while asking, highlighted once shown.
    private func lineView(highlight: Bool) -> some View {
        let blank = "＿＿"
        var a = AttributedString(moment.before)
        var mid = AttributedString(highlight ? moment.piece : blank)
        mid.foregroundColor = highlight ? Brand.violet : Brand.ink3
        mid.underlineStyle = highlight ? .single : nil
        a.append(mid)
        a.append(AttributedString(moment.after))
        // Romaji support without giving the answer away.
        let romaji = highlight ? Romanize.pronounced(moment.ja)
            : [Romanize.pronounced(moment.before), "___", Romanize.pronounced(moment.after)].filter { !$0.isEmpty }.joined(separator: " ")
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(a).font(Brand.jp(26, bold: true, relativeTo: .title2)).foregroundStyle(Brand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(romaji).font(.callout).foregroundStyle(Brand.violetDeep)
            }
            Spacer(minLength: 8)
            if highlight {
                Button { Speech.shared.say(moment.ja) } label: {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Brand.violetDeep)
                        .frame(width: 44, height: 44).background(Brand.violetSoft, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Hear the line")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(highlight ? moment.ja : "\(moment.before), blank, \(moment.after)")
    }

    /// The other words in the line, translated: known ones ticked, new ones highlighted, so the question
    /// is only about the grammar. (The blanked piece is never glossed.)
    @ViewBuilder private var wordChips: some View {
        if !moment.words.isEmpty {
            WrapLayout(spacing: 6) {
                ForEach(moment.words, id: \.self) { w in
                    HStack(spacing: 5) {
                        Text(w.text).font(Brand.jp(15, bold: true)).foregroundStyle(Brand.ink)
                        Text(w.meaning).font(.footnote.weight(w.status == .new ? .semibold : .regular))
                            .foregroundStyle(w.status == .new ? Brand.sunDeep : Brand.ink2)
                        if w.status == .known {
                            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(Brand.success)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(w.status == .new ? Brand.sunSoft : Brand.mist, in: Capsule())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(w.text), \(w.meaning)\(w.status == .known ? ", you know this word" : w.status == .new ? ", new word" : "")")
                }
            }
            .accessibilityIdentifier("grammar-words")
        }
    }

    private var tipBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(moment.point.title).font(Brand.jp(17, bold: true)).foregroundStyle(Brand.violetDeep)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Brand.violetSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(moment.point.tip).font(.subheadline).foregroundStyle(Brand.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("grammar-tip")
    }

    private func result(_ ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ok ? (guided ? "Nice, you spotted it" : "\(moment.point.title) ✓") : "It's 「\(moment.piece)」 here",
                  systemImage: ok ? "checkmark.seal.fill" : "arrow.uturn.backward.circle.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(ok ? Brand.success : Brand.warn)
            if !guided { tipBox }
            Button("Continue") { session.finishGrammar(correct: ok, guided: guided) }
                .buttonStyle(.brandPrimary)
                .accessibilityIdentifier("grammar-continue")
        }
    }
}

/// Which rung of the ladder this card is: "Chunks · を".
struct LadderChip: View {
    let stage: LadderStage
    let point: GrammarPoint

    var body: some View {
        Label(point.tier >= 2 ? "Pattern" : "Chunk", systemImage: "square.stack.3d.up.fill")
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Brand.violet, in: Capsule())
            .accessibilityLabel("\(point.tier >= 2 ? "Pattern" : "Chunk") question. Your level: \(stage.title)")
    }
}

/// The ladder in Progress: where the learner is and what unlocks the next rung.
struct LadderCard: View {
    let wordsLearned: Int
    var dailyGoal = 20
    @ObservedObject var grammar = GrammarBook.shared
    @ObservedObject private var kana = KanaProgress.shared

    var body: some View {
        let stage = LadderStage.current(wordsLearned: wordsLearned, grammar: grammar)
        VStack(alignment: .leading, spacing: 14) {
            // What's next in full (preview, kana tiles, path); Home only shows the essentials.
            UnlockDetailCard(wordsLearned: wordsLearned, dailyGoal: dailyGoal)
            Text("Now: \(stage.title) · \(stage.blurb)").font(.subheadline).foregroundStyle(Brand.ink)
            let met = grammar.points.values.sorted { GrammarCatalog.order($0.id) < GrammarCatalog.order($1.id) }
            if !met.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(met) { g in
                        if let p = GrammarCatalog.byId[g.id] {
                            Text(p.title).font(Brand.jp(14, bold: g.isSolid))
                                .foregroundStyle(g.isSolid ? Brand.success : Brand.violetDeep)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(g.isSolid ? Brand.successSoft : Brand.violetSoft, in: Capsule())
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Grammar met: \(met.compactMap { GrammarCatalog.byId[$0.id]?.title }.joined(separator: ", "))")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ladder-card")
    }
}
