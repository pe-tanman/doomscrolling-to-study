#if DEBUG
import UIKit

/// Question Lab: fire any card type on the current Short without waiting for the feed to produce it.
enum LabQuestion: String, CaseIterable, Identifiable {
    case learn = "New word", recall = "Recall (met before)", recallToJapanese = "Recall · EN → JP", listen = "Kana sound drill"
    case pictureWhat = "Picture · what's this?", pictureColor = "Picture · what color?", pictureWhich = "Picture · which one?"
    case reviewToMeaning = "Review · JP → meaning", reviewToJapanese = "Review · EN → JP"
    case reviewListen = "Review · hear it", reviewSpell = "Review · spell it", reviewSay = "Review · say it"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .learn: return "sparkle"
        case .recall, .recallToJapanese: return "brain.head.profile"
        case .listen: return "ear"
        case .pictureWhat, .pictureColor, .pictureWhich: return "photo"
        case .reviewToMeaning, .reviewToJapanese: return "arrow.triangle.2.circlepath"
        case .reviewListen: return "ear.and.waveform"
        case .reviewSpell: return "square.grid.3x2"
        case .reviewSay: return "mic"
        }
    }
}

extension FeedSession {
    /// Shows `q` for `entry` (or a random word at the learner's level) over the current Short.
    func labShow(_ q: LabQuestion, entry chosen: VocabEntry? = nil) async {
        let lv = settings.jlptLevel
        let pool = q.isPicture ? Self.pictureWords.compactMap { vocab.byId[$0] } : vocab.entries.filter { $0.level == lv }
        guard var entry = chosen ?? pool.randomElement() ?? vocab.entries.first else { return }
        let vid = currentVideoId ?? "lab"
        let line = "Today's word: \(entry.en.first ?? entry.meaning)"
        let swap = vocab.candidates(in: line, allSenses: true).first { $0.entry.id == entry.id }?.range
        var shownLine = line
        var kind = MomentKind.learn
        func opts(_ e: VocabEntry) -> [VocabEntry] { (vocab.distractors(for: e, count: 2) + [e]).shuffled() }

        switch q {
        case .learn: break
        case .recall: kind = .recall(options: opts(entry), toJapanese: false)
        case .recallToJapanese: kind = .recall(options: opts(entry), toJapanese: true)
        case .listen:
            let k = KanaProgress.shared.nextDrill()   // a sound not picked right yet, like the feed does
            entry = Kana.drillEntry(k)
            kind = .listen(options: Kana.drillOptions(for: k).map { Kana.drillEntry($0) }, kanaDrill: true)
            shownLine = ""
        case .pictureWhat, .pictureColor, .pictureWhich:
            let frame = await FrameGrabber.grab(web.webView)
            if let frame { frames[vid] = (frame.image, frame.screenRect) }
            let box = q == .pictureWhich ? CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) : CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
            var ask = PictureAsk.whatsThis
            if q == .pictureWhich { ask = .whichOne }
            if q == .pictureColor, let c = Self.colorWords.compactMap({ vocab.byId[$0] }).randomElement() {
                ask = .color(of: entry); entry = c
            }
            kind = .picture(options: opts(entry), ask: ask, frame: frame?.image, frameRect: frame?.screenRect, box: box)
            shownLine = ""
        case .reviewToMeaning, .reviewToJapanese:
            let toJa = q == .reviewToJapanese
            var o = vocab.distractors(for: entry, count: 2)
            if toJa { o = o.filter { $0.kana != entry.kana } }
            kind = .review(options: (o + [entry]).shuffled(), toJapanese: toJa, metIn: "My morning routine")
        case .reviewListen:
            kind = .hearIt(options: opts(entry), metIn: "My morning routine")
            shownLine = ""
            Speech.shared.say(entry.mainKana)
        case .reviewSpell:
            let e = pool.filter { Kana.spellTiles(for: $0.mainKana, extra: 2) != nil && !$0.isSuffix }.randomElement() ?? entry
            entry = chosen ?? e
            guard let t = Kana.spellTiles(for: entry.mainKana, extra: 2) else { return }
            kind = .spell(tiles: t.tiles, answer: t.answer, metIn: "My morning routine")
            shownLine = "Today's word: \(entry.meaning)"
        case .reviewSay:
            kind = .say(metIn: "My morning routine")
            shownLine = "Today's word: \(entry.meaning)"
        }
        moment = LearningMoment(videoId: vid, targetIndex: -99, entry: entry, line: shownLine,
                                swapRange: q == .learn || q == .recall || q == .recallToJapanese || q == .reviewToMeaning ? swap : nil,
                                japaneseLine: q == .learn ? "仕事の後でとても\(entry.kanji ?? entry.kana)" : nil,
                                numberInVideo: 1, totalInVideo: 1, kind: kind)
        web.pause()
        if case .listen = kind { Speech.shared.say(entry.kana) }
        appendLogPublic("lab \(q.rawValue): \(entry.kana)")
    }

    /// Real pipeline on the current Short: screenshot → Jev picture → bonus cards (server + review + drill).
    func labRunNonverbal() {
        guard let id = currentVideoId, var r = records[id] else { appendLogPublic("lab: no current Short"); return }
        r.targets = []; r.completed = []; r.bonus = []
        records[id] = r
        lastMomentEnded = .distantPast
        startNonverbal(id)
        appendLogPublic("lab: nonverbal pipeline on \(id)")
    }

    /// Any phrase × skill as an Upscroll original in the feed.
    func labShowOriginal(_ phrase: Phrase, skill: Skill) {
        moment = nil
        original = OriginalCard(phrase: phrase, skill: skill, place: Curriculum.place(of: phrase.id) ?? Curriculum.places[0])
        web.pause()
        Speech.shared.say(phrase.exampleKana)
    }

    /// Phrase from this Short: the real pipeline on the current Short when it has Japanese captions
    /// (candidates → Jev → card right away), otherwise a sample line.
    func labShowShortPhrase() {
        moment = nil
        if let id = currentVideoId, let r = records[id], !r.japaneseCues.isEmpty,
           let c = PhraseMaker.rulePick(PhraseMaker.candidates(source: r.sourceCues, japanese: r.japaneseCues, after: 0)) {
            let sp = ShortPhrase(id: "\(id)#\(c.i)", ja: c.ja, en: c.en, tiles: PhraseMaker.tiles(c.ja), videoId: id, title: r.info?.title ?? "")
            original = OriginalCard(phrase: sp.phrase, skill: .writing, place: PhraseBook.shared.place, source: sp)
        } else {
            let ja = "ちょっと待って！"
            let sp = ShortPhrase(id: "lab#\(Int(Date().timeIntervalSince1970))", ja: ja, en: "Wait a second!", tiles: PhraseMaker.tiles(ja),
                                 videoId: currentVideoId ?? "lab", title: "Lab")
            original = OriginalCard(phrase: sp.phrase, skill: .writing, place: PhraseBook.shared.place, source: sp)
        }
        web.pause()
        if let ja = original?.source?.ja { Speech.shared.say(ja) }
    }

    /// A lesson checkpoint card (the frame used by Upscroll lesson Shorts).
    func labShowLessonCheckpoint() {
        moment = nil
        let l = LessonVideo(id: "lab", youtubeId: currentVideoId ?? "lab", title: "Lab lesson", place: "arrival",
                            checkpoints: [.init(at: 0, kind: "phrase", phraseId: "thanks", skill: "reading")])
        guard let p = Curriculum.phraseById["thanks"] else { return }
        original = OriginalCard(phrase: p, skill: .reading, place: Curriculum.places[0], lesson: l)
        web.pause()
        Speech.shared.say(p.exampleKana)
    }

    func labHitDailyLimit() {
        web.pause()
        recapRequested = true
    }
}

extension LabQuestion {
    var isPicture: Bool { [.pictureWhat, .pictureColor, .pictureWhich].contains(self) }
}

extension FeedSession {
    /// A grammar card from the current Short's Japanese when one has a grammar point, else a sample line.
    func labShowGrammar(_ mode: GrammarMode) {
        moment = nil
        original = nil
        var line = (en: "I want to eat ramen", ja: "ラーメンが食べたい")
        var hit = GrammarCatalog.detect(in: line.ja).first
        if let id = currentVideoId, let r = records[id] {
            for c in PhraseMaker.candidates(source: r.sourceCues, japanese: r.japaneseCues, after: 0) {
                if let h = GrammarCatalog.detect(in: c.ja).first { line = (c.en, c.ja); hit = h; break }
            }
        }
        guard let h = hit else { return }
        let chunk = GrammarCatalog.chunk(before: h.before, piece: h.piece, after: h.after)
        let d = Array(h.distractors.prefix(2))
        grammar = GrammarMoment(videoId: currentVideoId ?? "lab", point: h.point, piece: h.piece, before: h.before, after: h.after,
                                options: ([h.piece] + d).shuffled(), mode: mode, en: line.en, ja: line.ja, title: "Lab",
                                pickedBy: "lab", chunk: chunk, bank: (chunk + d.prefix(1)).shuffled(),
                                words: Self.glossAround(h, vocab: vocab, book: wordBook) ?? [])
        web.pause()
        if mode == .notice { Speech.shared.say(line.ja) }
    }
}
#endif
