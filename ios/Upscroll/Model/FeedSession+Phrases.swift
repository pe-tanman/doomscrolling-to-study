import Foundation

/// Phrases from any Short, and Upscroll lesson Shorts inside the feed.
extension FeedSession {
    // MARK: Phrase from this Short

    /// Whole lines are the top of the ladder: none while learning words and chunks, a few once patterns
    /// start (every 5th captioned Short), then every 3rd once sentences are the learner's level.
    private var phraseGap: Int? {
        switch ladderStage {
        case .words, .chunks: return nil
        case .patterns: return 5
        case .sentences: return 3
        }
    }

    /// Pace rule shared by planning (so smart picks aren't spent on Shorts that won't show one) and showing.
    var phraseDueHere: Bool {
        guard settings.cardEvery != 0, settings.pauseOnWord, let phraseGap else { return false }
        if lastGrammarSwipe == swipesThisSession { return false }   // one structured card per Short
        guard let last = lastPhraseSwipe, last <= swipesThisSession else { return true }
        return swipesThisSession - last >= phraseGap
    }

    /// Captions and their Japanese are in: choose the line to learn whole (Jev when online, else the offline rule).
    func planPhrase(_ id: String) {
        guard var r = records[id], r.phraseRequested != true, r.isAd != true, r.isDubbed != true,
              !r.sourceCues.isEmpty, !r.japaneseCues.isEmpty,
              LessonLibrary.shared.lesson(youtubeId: id) == nil, phraseDueHere else { return }
        let playedTo = id == currentVideoId ? currentTime : 0
        // i + 1: a whole line may bring at most one grammar point the learner hasn't met yet.
        let cands = PhraseMaker.candidates(source: r.sourceCues, japanese: r.japaneseCues, after: playedTo)
            .filter { !PhraseBook.shared.contains("\(id)#\($0.i)") && GrammarCatalog.unmet(in: $0.ja, book: GrammarBook.shared).count <= 1 }
        guard !cands.isEmpty else { return }
        r.phraseRequested = true
        setRecord(r, for: id)
        let title = r.info?.title ?? ""
        if settings.smartPicks, LessonClient.baseURL != nil, Plan.allows(.smartPicks) {
            let req = PhraseRequest(videoId: id, title: title, goal: settings.goal, lines: cands.map { .init(i: $0.i, en: $0.en, ja: $0.ja) },
                                    learner: learnerDTO)
            Task { @MainActor in
                do {
                    let resp = try await LessonClient.phrase(req)
                    if let p = resp.picks.first, let c = cands.first(where: { $0.i == p.i }) {
                        setPhrase(id, c, by: "jev")
                    } else {
                        appendLogPublic("phrase \(id): Jev found no good line")
                    }
                } catch {
                    // YouTube's Japanese is machine translation, often word-for-word: never teach a line Jev didn't check.
                    appendLogPublic("phrase \(id): \(error.localizedDescription), no unchecked line")
                }
            }
        }
    }

    private func setPhrase(_ id: String, _ c: (i: Int, en: String, ja: String), by: String) {
        guard var r = records[id], r.phraseCue == nil else { return }
        r.phraseCue = c.i; r.phraseJa = c.ja; r.phraseEn = c.en; r.phrasePickedBy = by
        setRecord(r, for: id)
        appendLogPublic("phrase \(id) (\(by)): \(c.ja) = \(c.en)")
    }

    /// While a phrase is planned on this Short, the word on the same line (and, for beginners, the second word)
    /// stays in the subtitles only, so the Short pauses about as often as before.
    func phraseSuppresses(_ target: VideoTarget, index: Int, in r: VideoRecord) -> Bool {
        guard let pc = r.phraseCue, r.phraseDone != true || lastPhraseSwipe == swipesThisSession else { return false }
        return target.cueIndex == pc || index > 0
    }

    /// When the picked line finishes playing: pause and teach it as a whole phrase. Returns true when shown.
    func checkPhraseMoment(_ id: String, _ r: inout VideoRecord) -> Bool {
        guard let pc = r.phraseCue, r.phraseDone != true, pc < r.sourceCues.count,
              let ja = r.phraseJa, let en = r.phraseEn else { return false }
        let cue = r.sourceCues[pc]
        let next = pc + 1 < r.sourceCues.count ? r.sourceCues[pc + 1].start : cue.end
        let lineEnd = max(cue.start + 0.6, min(cue.end, next))
        if currentTime > lineEnd + 2.5 { r.phraseDone = true; records[id] = r; return false }   // swiped back / seeked past
        guard currentTime >= lineEnd - 0.2 else { return false }
        r.phraseDone = true
        records[id] = r
        guard phraseDueHere else { return false }
        let sp = ShortPhrase(id: "\(id)#\(pc)", ja: ja, en: en, tiles: PhraseMaker.tiles(ja), videoId: id,
                             title: r.info?.title ?? "", pickedBy: r.phrasePickedBy ?? "rules")
        lastPhraseSwipe = swipesThisSession
        lastCardSwipe = swipesThisSession
        original = OriginalCard(phrase: sp.phrase, skill: .writing, place: PhraseBook.shared.place, source: sp)
        web.pause()
        Speech.shared.say(ja)
        appendLogPublic("phrase moment \(ja) at \(String(format: "%.1f", currentTime))s")
        return true
    }

    // MARK: Lesson Shorts

    /// Every ~8 swipes, if a lesson suits this learner (their current place, then their goal): play it next.
    func maybeShowLesson() -> Bool {
        guard settings.originals, !recapRequested, swipesThisSession >= 4, swipesSinceLesson >= 8,
              let l = LessonLibrary.shared.next(place: journey.currentPlace.id, goal: settings.goal) else { return false }
        playLesson(l)
        return true
    }

    /// Open a lesson Short in the feed (also from the Home shelf). YouTube keeps the feed going after it.
    func playLesson(_ l: LessonVideo) {
        swipesSinceLesson = 0
        openingLesson = currentVideoId != nil
        moment = nil
        original = nil
        appendLogPublic("lesson \(l.id) → \(l.youtubeId)")
        web.open(l.url)
    }

    /// Pause at each checkpoint and show its card (a curriculum phrase practice, or a word card).
    func checkLessonCheckpoint(_ l: LessonVideo) {
        guard moment == nil, original == nil else { return }
        for (n, cp) in l.checkpoints.enumerated() where !lessonCheckpointsDone.contains(n) {
            guard currentTime >= cp.at else { return }
            lessonCheckpointsDone.insert(n)
            if currentTime > cp.at + 4 { continue }   // seeked past it
            if cp.kind == "phrase", let pid = cp.phraseId, let phrase = Curriculum.phraseById[pid],
               let place = Curriculum.place(of: pid) {
                let skill = cp.skill.flatMap(Skill.init(rawValue:)) ?? .reading
                original = OriginalCard(phrase: phrase, skill: skill, place: place, lesson: l)
                web.pause()
                if skill != .listening { Speech.shared.say(phrase.exampleKana) }
                return
            }
            if cp.kind == "word", let eid = cp.entryId, let entry = vocab.byId[eid] {
                moment = LearningMoment(videoId: l.youtubeId, targetIndex: -1, entry: entry, line: l.title, swapRange: nil,
                                        japaneseLine: nil, numberInVideo: n + 1, totalInVideo: l.checkpoints.count, fromTitle: true)
                wordBook.recordEncounter(entry, context: WordContext(videoId: l.youtubeId, title: l.title, line: l.title,
                                                                     japaneseLine: nil, date: Date()))
                web.pause()
                Speech.shared.say(entry.kana)
                return
            }
        }
    }
}
