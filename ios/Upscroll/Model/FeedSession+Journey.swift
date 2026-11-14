import Foundation
import UIKit

/// An Upscroll original between real Shorts: built for the phrase you're missing most.
struct OriginalCard: Identifiable, Equatable {
    enum Kind: Equatable { case miniReel, quest, fromShort, lesson }
    let id = UUID()
    let phrase: Phrase
    let skill: Skill
    let place: Place
    /// A word the learner just met in the feed that this phrase uses (bridges word → full phrase).
    var fromFeedWord: VocabEntry? = nil
    /// A new phrase taken from the Short on screen (learn it, then build it).
    var source: ShortPhrase? = nil
    /// A checkpoint of an Upscroll lesson Short.
    var lesson: LessonVideo? = nil
    var kind: Kind {
        if source != nil { return .fromShort }
        if lesson != nil { return .lesson }
        return skill == .listening ? .miniReel : .quest
    }
}

/// Curriculum v2 wiring: time & Japanese time, coverage dots from the feed, originals.
extension FeedSession {
    /// Japanese audio = the video's own auto-captions are Japanese.
    func isJapaneseAudio(_ id: String?) -> Bool {
        guard let id, let r = records[id], r.isAd != true, r.isDubbed != true else { return false }   // dubbed ≠ real Japanese speech
        if r.info?.tracks.contains(where: { $0.kind == "asr" && $0.languageCode.hasPrefix("ja") }) == true { return true }
        return false
    }

    /// Once a second: count feed time (and Japanese time), check the daily limit.
    func clockTick() {
        guard !dashboardOpen, onShorts, UIApplication.shared.applicationState == .active, !recapRequested else { return }
        let busy = moment != nil || original != nil || grammar != nil
        guard busy || !paused else { return }
        // Japanese time: a word card, Japanese audio, or a Japanese word in the subtitles on screen.
        let audio = isJapaneseAudio(currentVideoId)
        journey.addFeedTime(1, japanese: busy || audio || currentSwap != nil, audio: audio)
        let limit = settings.dailyLimitMinutes
        let day = JourneyStore.dayKey(Date())
        if limit > 0, journey.today.scrollSeconds >= Double(limit * 60), limitRecapShownDay != day, moment == nil, original == nil {
            limitRecapShownDay = day
            web.pause()
            recapRequested = true
        }
    }

    /// Japanese-audio Short: each caption line that finished playing counts as heard,
    /// and phrases in it fill the listening dot.
    func hearJapaneseLines(_ id: String, from: Double, to: Double) {
        guard id == currentVideoId, isJapaneseAudio(id), to > from, to - from < 3, let r = records[id] else { return }
        for cue in r.sourceCues where cue.end > max(from, lastHeardTime) && cue.end <= to {
            journey.heardLine()
            noticePhrases(in: cue.text, skill: .listening)
        }
        lastHeardTime = to
    }

    /// Mark a skill dot for every curriculum phrase that appears in a Japanese line.
    func noticePhrases(in line: String, skill: Skill) {
        for p in Curriculum.allPhrases where p.appears(in: line) {
            journey.noteExample(p.id, line: line)
            if journey.mark(p.id, skill) { appendLogPublic("dot \(skill.rawValue) \(p.id)") }
        }
    }

    /// ~1 in 6 swipes; never in the first 3 swipes, never two in a row, at most 3 per 10 minutes.
    func maybeShowOriginal() {
        #if DEBUG
        let force = ProcessInfo.processInfo.arguments.contains("-forceOriginal")
        #else
        let force = false
        #endif
        guard settings.originals, moment == nil, original == nil, grammar == nil else { return }
        originalTimes.removeAll { $0 < Date().addingTimeInterval(-600) }
        if !force {
            // First full-phrase card comes right after the 3rd swipe, so a beginner meets a usable phrase early.
            guard swipesThisSession > 3, swipesSinceOriginal >= (originalTimes.isEmpty ? 3 : 6), originalTimes.count < 3 else { return }
        } else if !originalTimes.isEmpty { return }
        let place = journey.currentPlace
        // No speaking tasks when the learner turned them off or refused the mic / speech recognition.
        let canSpeak = settings.speakingInFeed && !SpeechCheck.permissionDenied
        let gaps = journey.gaps(place).map { g in (phrase: g.phrase, missing: canSpeak ? g.missing : g.missing.filter { $0 != .speaking }) }
            .filter { !$0.missing.isEmpty }
        // The skill the learner's path focuses on (Jev) goes first; the rest keep their usual order.
        let focus = PathStore.shared.focus.flatMap { canSpeak || $0 != .speaking ? $0 : nil }
        func ordered(_ base: [Skill]) -> [Skill] { focus.map { f in [f] + base.filter { $0 != f } } ?? base }
        // Every other original: a phrase from the learner's own Shorts, when one is missing a skill.
        let mine = PhraseBook.shared.gaps(canSpeak: canSpeak)
        if !mine.isEmpty, gaps.isEmpty || originalTimes.count % 2 == 1 {
            let g = mine[0]
            if let skill = ordered([.listening, .reading, .writing, .speaking]).first(where: { g.missing.contains($0) }) {
                original = OriginalCard(phrase: g.phrase.phrase, skill: skill, place: PhraseBook.shared.place)
                originalTimes.append(Date())
                swipesSinceOriginal = 0
                web.pause()
                if skill != .listening { Speech.shared.say(g.phrase.ja) }
                return
            }
        }
        // Prefer a phrase that uses a word just met in the feed: word noticed → whole sentence to say.
        let recent = wordBook.metToday.prefix(15).compactMap { vocab.byId[$0.id] }
        for g in gaps {
            if let w = recent.first(where: { w in g.phrase.example.contains(w.kana) || (w.kanji.map { g.phrase.example.contains($0) } ?? false) }),
               let skill = ordered([Skill.reading, .speaking, .listening, .writing]).first(where: { g.missing.contains($0) }) {
                original = OriginalCard(phrase: g.phrase, skill: skill, place: place, fromFeedWord: w)
                originalTimes.append(Date())
                swipesSinceOriginal = 0
                web.pause()
                Speech.shared.say(g.phrase.exampleKana)
                return
            }
        }
        // Listening first (it needs Japanese audio), then reading, writing, speaking.
        for skill in ordered([Skill.listening, .reading, .writing, .speaking]) {
            if let g = gaps.first(where: { $0.missing.contains(skill) }) {
                original = OriginalCard(phrase: g.phrase, skill: skill, place: place)
                originalTimes.append(Date())
                swipesSinceOriginal = 0
                web.pause()
                Speech.shared.say(g.phrase.exampleKana)
                return
            }
        }
    }

    func finishOriginal(correct: Bool) {
        if let o = original {
            if var sp = o.source {
                // A new phrase from this Short joins "My phrases" either way: it was read (and maybe built).
                sp.skills.insert(.reading)
                if correct { sp.skills.insert(o.skill) }
                PhraseBook.shared.add(sp)
            } else if o.phrase.id.hasPrefix("short:") {
                if correct { PhraseBook.shared.mark(o.phrase.id, o.skill) }
            } else if correct {
                journey.mark(o.phrase.id, o.skill)
            }
        }
        original = nil
        web.play()
        checkUnlocks()
    }

    /// Skip a phrase-from-this-Short card without saving it.
    func dismissOriginal() {
        original = nil
        web.play()
    }

    /// After a good stop (or a long break): the next scroll is a new session.
    func startNewSession() {
        journey.startSession(words: wordBook.words.count)
        swipesThisSession = 0
        recapRequested = false
    }
}
