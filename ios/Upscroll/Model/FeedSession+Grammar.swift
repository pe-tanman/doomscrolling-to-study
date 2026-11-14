import Foundation

/// A chunk / pattern question on the Short being watched: a blank in its own Japanese line.
struct GrammarMoment: Identifiable, Equatable {
    let id = UUID()
    let videoId: String
    let point: GrammarPoint
    let piece: String
    let before: String
    let after: String
    /// The piece and its clearly-wrong alternatives, shuffled.
    let options: [String]
    let mode: GrammarMode
    let en: String
    let ja: String
    let title: String
    /// "jev" (checked: right grammar, good translation, one right answer) or "rules" (offline).
    let pickedBy: String
    /// Build mode: the chunk in order, and the tiles to build it from (one wrong tile mixed in).
    let chunk: [String]
    let bank: [String]
    /// The other words in the line with their meanings (known ones ticked, new ones translated).
    var words: [WordGloss] = []

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

extension FeedSession {
    // MARK: Ladder

    /// Where this learner is on the word → chunk → pattern → sentence ladder.
    var ladderStage: LadderStage {
        LadderStage.current(wordsLearned: wordBook.learnedCount, grammar: GrammarBook.shared)
    }

    var learnerDTO: LearnerDTO {
        LearnerDTO(stage: ladderStage.title.lowercased(), wordsLearned: wordBook.learnedCount, known: GrammarBook.shared.knownTitles)
    }

    /// Grammar card pace: chunk learners every 3rd captioned Short; sentence learners every 4th (sentences take over).
    var grammarDueHere: Bool {
        guard settings.cardEvery != 0, settings.pauseOnWord else { return false }
        let gap: Int
        switch ladderStage {
        case .words: return false
        case .chunks, .patterns: gap = 3
        case .sentences: gap = 4
        }
        if lastPhraseSwipe == swipesThisSession { return false }   // one structured card per Short
        guard let last = lastGrammarSwipe, last <= swipesThisSession else { return true }
        return swipesThisSession - last >= gap
    }

    /// Captions arrived: plan the Short's structured card for this learner's rung of the ladder.
    func planStructure(_ id: String) {
        planGrammar(id)
        planPhrase(id)
    }

    // MARK: Planning

    func planGrammar(_ id: String) {
        guard var r = records[id], r.grammarRequested != true, r.isAd != true, r.isDubbed != true,
              !r.sourceCues.isEmpty, !r.japaneseCues.isEmpty,
              LessonLibrary.shared.lesson(youtubeId: id) == nil, grammarDueHere else { return }
        let stage = ladderStage
        let book = GrammarBook.shared
        let allowed = book.eligible(maxTier: stage.maxTier)
        let playedTo = id == currentVideoId ? currentTime : 0

        // Every (line, grammar point) the learner may be asked now, from YouTube's Japanese for each caption.
        // Each candidate also carries the other words of its line: the question must be about the grammar, so
        // lines are skipped when a word can't be translated, or when more than 2 words are new to the learner.
        var found: [(i: Int, en: String, ja: String, hit: GrammarHit, words: [WordGloss], newWords: Int)] = []
        for (i, cue) in r.sourceCues.enumerated() where cue.start >= playedTo + 1 {
            let en = cue.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...14).contains(en.split(separator: " ").count), !en.contains("["), !en.contains("♪"), !en.contains("http"),
                  let ja = PhraseMaker.bestOverlap(cue, r.japaneseCues)?.text.trimmingCharacters(in: .whitespacesAndNewlines),
                  Romanize.isJapanese(ja), (2...24).contains(ja.count) else { continue }
            for h in GrammarCatalog.detect(in: ja, maxTier: stage.maxTier) where allowed.contains(h.point.id) {
                guard let words = Self.glossAround(h, vocab: vocab, book: wordBook) else { continue }
                let newWords = words.filter { $0.status == .new }.count
                guard newWords <= 2 else { continue }
                found.append((i, en, ja, h, words, newWords))
            }
            if found.count >= 16 { break }
        }
        guard !found.isEmpty else { return }
        // Due first, then still-learning, then new (in ladder order); within that, lines made of known words first.
        let rank: (String) -> Int = { ["due": 0, "learning": 1, "new": 2, "known": 3][book.status($0)] ?? 2 }
        let cands = Array(found.sorted { (rank($0.hit.point.id), $0.newWords, GrammarCatalog.order($0.hit.point.id), $0.i)
                                       < (rank($1.hit.point.id), $1.newWords, GrammarCatalog.order($1.hit.point.id), $1.i) }.prefix(8))
        r.grammarRequested = true
        setRecord(r, for: id)

        // The line is YouTube's machine translation: without Jev's check that it's natural Japanese
        // (not word-for-word), there is no grammar question on this Short.
        guard settings.smartPicks, LessonClient.baseURL != nil, Plan.allows(.smartPicks) else { return }
        var lines: [Int: GrammarRequest.Line] = [:]
        for c in cands {
            let ws = (lines[c.i]?.words ?? []) + c.words.map { GrammarRequest.Word(ja: $0.text, meaning: $0.meaning, known: $0.status == .known) }
            var seen = Set<String>()
            lines[c.i] = .init(i: c.i, en: c.en, ja: c.ja, words: ws.filter { seen.insert($0.ja).inserted })
        }
        let req = GrammarRequest(
            videoId: id, title: r.info?.title ?? "", learner: learnerDTO,
            lines: lines.values.sorted { $0.i < $1.i },
            candidates: cands.map { c in
                .init(line: c.i, point: c.hit.point.id, title: c.hit.point.title, meaning: c.hit.point.meaning,
                      piece: c.hit.piece, before: c.hit.before, after: c.hit.after,
                      distractors: c.hit.distractors, status: book.status(c.hit.point.id))
            })
        Task { @MainActor in
            do {
                let resp = try await LessonClient.grammar(req)
                if let p = resp.picks.first, let c = cands.first(where: { $0.i == p.line && $0.hit.point.id == p.point }) {
                    setGrammar(id, line: c.i, en: c.en, ja: c.ja, hit: c.hit, distractors: p.distractors, by: "jev")
                } else {
                    appendLogPublic("grammar \(id): Jev found no clear question")
                }
            } catch {
                appendLogPublic("grammar \(id): \(error.localizedDescription), no unchecked line")
            }
        }
    }

    private func setGrammar(_ id: String, line: Int, en: String, ja: String, hit: GrammarHit, distractors: [String], by: String) {
        guard var r = records[id], r.grammarCue == nil else { return }
        r.grammarCue = line
        r.grammarPoint = hit.point.id
        r.grammarPiece = hit.piece
        r.grammarBefore = hit.before
        r.grammarAfter = hit.after
        r.grammarDistractors = distractors
        r.grammarJa = ja
        r.grammarEn = en
        r.grammarPickedBy = by
        setRecord(r, for: id)
        appendLogPublic("grammar \(id) (\(by)): \(hit.before)【\(hit.piece)】\(hit.after) = \(en) · \(hit.point.id)")
    }

    // MARK: Showing

    /// When the picked line finishes playing: pause and ask about the chunk. Returns true when shown.
    func checkGrammarMoment(_ id: String, _ r: inout VideoRecord) -> Bool {
        guard let gc = r.grammarCue, r.grammarDone != true, gc < r.sourceCues.count,
              let pid = r.grammarPoint, let point = GrammarCatalog.byId[pid], let piece = r.grammarPiece,
              let ja = r.grammarJa, let en = r.grammarEn else { return false }
        let cue = r.sourceCues[gc]
        let next = gc + 1 < r.sourceCues.count ? r.sourceCues[gc + 1].start : cue.end
        let lineEnd = max(cue.start + 0.6, min(cue.end, next))
        if currentTime > lineEnd + 2.5 { r.grammarDone = true; records[id] = r; return false }   // swiped back / seeked past
        guard currentTime >= lineEnd - 0.2 else { return false }
        r.grammarDone = true
        records[id] = r
        guard grammarDueHere else { return false }

        let before = r.grammarBefore ?? "", after = r.grammarAfter ?? ""
        let distractors = Array((r.grammarDistractors ?? []).prefix(2))
        let chunk = GrammarCatalog.chunk(before: before, piece: piece, after: after)
        let hit = GrammarHit(point: point, piece: piece, before: before, after: after, distractors: distractors)
        let words = Self.glossAround(hit, vocab: vocab, book: wordBook) ?? []
        let canBuild = chunk.count >= 2 && distractors.count >= 1
        let mode = GrammarBook.shared.mode(for: pid, canBuild: canBuild)
        let m = GrammarMoment(videoId: id, point: point, piece: piece, before: before, after: after,
                              options: ([piece] + distractors).shuffled(), mode: mode, en: en, ja: ja,
                              title: r.info?.title ?? "", pickedBy: r.grammarPickedBy ?? "rules",
                              chunk: chunk, bank: (chunk + distractors.prefix(1)).shuffled(), words: words)
        lastGrammarSwipe = swipesThisSession
        lastCardSwipe = swipesThisSession
        grammar = m
        web.pause()
        // First meeting: hear the line with the chunk in it. Otherwise the sound would give the answer away.
        if mode == .notice { Speech.shared.say(ja) } else { Speech.shared.prefetch(ja) }
        appendLogPublic("grammar moment \(pid) \(mode.rawValue) at \(String(format: "%.1f", currentTime))s")
        return true
    }

    /// Words before and after the blank (never the piece itself, so the gloss can't give the answer away).
    static func glossAround(_ h: GrammarHit, vocab: VocabStore, book: WordBook) -> [WordGloss]? {
        guard let a = GrammarGloss.gloss(h.before, vocab: vocab, book: book),
              let b = GrammarGloss.gloss(h.after, vocab: vocab, book: book) else { return nil }
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0.entryId).inserted }
    }

    /// While a grammar or phrase card is planned on this Short, words on the same line stay in the subtitles only.
    func structureSuppresses(_ target: VideoTarget, index: Int, in r: VideoRecord) -> Bool {
        if let gc = r.grammarCue, r.grammarDone != true || lastGrammarSwipe == swipesThisSession,
           target.cueIndex == gc || index > 0 { return true }
        return phraseSuppresses(target, index: index, in: r)
    }

    /// Skipped: not counted either way.
    func skipGrammar() {
        grammar = nil
        lastMomentEnded = Date()
        web.play()
    }

    func finishGrammar(correct: Bool, guided: Bool) {
        if let g = grammar {
            GrammarBook.shared.record(g.point.id, correct: correct, guided: guided,
                                      example: GrammarExample(ja: g.ja, en: g.en, videoId: g.videoId, title: g.title))
            // Curriculum phrases in the line get their dot: reading for a pick, writing for a build.
            if correct { noticePhrases(in: g.ja, skill: g.mode == .build ? .writing : .reading) }
            appendLogPublic("grammar \(g.point.id) \(correct ? "right" : "wrong")\(guided ? " (guided)" : "") → stage \(ladderStage.title)")
        }
        grammar = nil
        lastMomentEnded = Date()
        web.play()
        checkUnlocks()
    }
}
