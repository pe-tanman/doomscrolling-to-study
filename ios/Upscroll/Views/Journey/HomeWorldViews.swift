import SwiftUI

// MARK: - Home

struct HomeView: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    var onKeepScrolling: () -> Void
    /// Opens the Progress tab (from the next-unlock card).
    var onShowProgress: () -> Void = {}
    @State private var showSettings = false
    @ObservedObject private var rewards = Rewards.shared
    @State private var showSignIn = false
    /// "Not now" on the sign-in card hides it for 3 days (seconds since 1970; 0 = never dismissed).
    @AppStorage("signInCardHiddenUntil") private var signInCardHiddenUntil: Double = 0
    @ObservedObject private var auth = SupabaseAuth.shared
    @State private var insightIndex = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    @State private var detail: VocabEntry?

    private var level: Int { session.settings.jlptLevel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.fill").foregroundStyle(Brand.ink2)
                            .frame(width: 40, height: 40).background(.white.opacity(0.85), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Me and settings")
                    .accessibilityIdentifier("open-settings")
                    Spacer()
                    // Icons, not sentences: streak, streak freezes, skip tickets.
                    HStack(spacing: 10) {
                        iconCount("flame.fill", wordBook.streak, Brand.sunDeep, "\(wordBook.streak)-day streak")
                        iconCount(RewardIcon.freeze.symbol, rewards.freezes, RewardIcon.freeze.color, "\(rewards.freezes) streak freezes")
                        iconCount(RewardIcon.skip.symbol, rewards.skips, RewardIcon.skip.color, "\(rewards.skips) skip tickets")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.white.opacity(0.85), in: Capsule())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home-inventory")
                }
                if journey.today.goodStops > 0 { giftCard }
                // A few spare minutes? One clear "do this now" when words are due; scrolling becomes secondary.
                let due = wordBook.dueWords.count
                if due > 0 {
                    NavigationLink { ReviewTab(session: session, wordBook: wordBook) } label: {
                        HStack(spacing: 12) {
                            MascotImage(mood: .sleepy, size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Review \(min(due, ReviewTab.quickSet))").font(.headline).foregroundStyle(.white)
                                Label("1 min", systemImage: "timer").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white)
                        }
                        .padding(14)
                        .background(Brand.violet, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-quick-review")
                }
                // Right under Review: save progress to an account (with the one-time sign-in gift).
                if SupabaseAuth.isConfigured, !auth.isSignedIn, Date().timeIntervalSince1970 >= signInCardHiddenUntil {
                    signInCard
                }
                // The whole journey at a glance (World lives here now), then the route step by step.
                JourneyHero(session: session, wordBook: wordBook, journey: journey)
                // The essentials of what unlocks next (kana in one line); the full picture is in Progress.
                NextUnlockCard(wordsLearned: wordBook.learnedCount, dailyGoal: session.settings.dailyGoal, onOpen: onShowProgress)
                PathStrip(session: session, wordBook: wordBook, journey: journey)
                if due > 0 {
                    Button(action: onKeepScrolling) { Label("Keep scrolling", systemImage: "play.fill") }
                        .buttonStyle(.brandQuiet)
                        .accessibilityIdentifier("keep-scrolling")
                } else {
                    Button(action: onKeepScrolling) { Label("Keep scrolling", systemImage: "play.fill") }
                        .buttonStyle(.brandPrimary)
                        .accessibilityIdentifier("keep-scrolling")
                }
                wordsCard
                MyPhrasesCard()
                LessonShelf(session: session, journey: journey, onPlay: onKeepScrolling)
                insightCard
                pickups
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Brand.sky
                Image("scene_sky").resizable().scaledToFill().frame(height: 300).clipped()
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsTab(session: session, wordBook: wordBook) }
        }
        .onChange(of: session.settings.goal) { _, _ in
            PathStore.shared.update(session: session, journey: journey, wordBook: wordBook, force: true)
        }
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .sheet(item: $detail) { e in
            WordDetailSheet(entry: e, progress: wordBook.progress(e.id), level: session.settings.scriptLevel, onClose: { detail = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Small secondary card under Review: save progress (with the one-time gift), one tap to sign in.
    private var signInCard: some View {
        let words = wordBook.words.count
        let title = words == 0 ? "Save your progress" : "Save your \(words) word\(words == 1 ? "" : "s")"
        return HStack(spacing: 10) {
            Image(systemName: "icloud.and.arrow.up.fill").font(.body).foregroundStyle(Brand.violet)
                .frame(width: 34, height: 34).background(.white, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                if !rewards.signInGiftClaimed {
                    RewardText.signInGiftShort()
                        .font(.caption).foregroundStyle(Brand.ink2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityLabel("Sign-in gift: \(Rewards.signInGiftText)")
                }
            }
            Spacer(minLength: 4)
            Button("Sign in") { showSignIn = true }
                .font(.subheadline.weight(.bold)).foregroundStyle(Brand.violetDeep)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(.white, in: Capsule())
                .accessibilityIdentifier("home-sign-in")
            Button { signInCardHiddenUntil = Date().addingTimeInterval(3 * 86400).timeIntervalSince1970 } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Brand.ink3)
                    .frame(width: 28, height: 34)
            }
            .accessibilityLabel("Not now")
            .accessibilityIdentifier("home-sign-in-later")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Brand.violetSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sign-in-nudge")
    }

    /// The dashboard: one big number, four labelled tiles, the level bar. No legend needed.
    private var wordsCard: some View {
        let total = session.vocab.countByLevel[level] ?? 1
        let n = wordBook.learnedCount(level: level, vocab: session.vocab)
        // Answered right at least once but not yet past the 3-day "learned" bar.
        let almost = wordBook.words.values.filter { $0.correct > 0 && !$0.isLearned }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(wordBook.learnedCount)").font(.system(size: 48, weight: .heavy, design: .rounded)).foregroundStyle(Brand.violetDeep)
                    .contentTransition(.numericText())
                Text("words learned").font(.title3.weight(.semibold)).foregroundStyle(Brand.ink)
                Spacer()
                Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(Brand.success)
            }
            HStack(spacing: 8) {
                statTile("sun.max.fill", wordBook.metToday.count, "today", Brand.sunDeep, Brand.sunSoft)
                statTile("sparkle", wordBook.newToday, "new", Brand.violetDeep, Brand.violetSoft)
                statTile("eye.fill", wordBook.words.count, "met", Skill.reading.color, Skill.reading.soft)
                statTile("lock.open.fill", almost, "almost", Brand.success, Brand.successSoft)
                    .accessibilityIdentifier("on-the-way")
            }
            HStack(spacing: 10) {
                Text("N\(level)").font(.subheadline.weight(.bold)).foregroundStyle(Brand.violetDeep)
                ProgressBar(value: Double(n) / Double(max(1, total)))
                Text("\(n)/\(total)").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Level N\(level): \(n) of \(total) words learned")
        }
        .brandCard()
        .accessibilityIdentifier("words-learned")
    }

    private func statTile(_ symbol: String, _ value: Int, _ label: String, _ fg: Color, _ bg: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.subheadline.weight(.bold)).foregroundStyle(fg)
            Text("\(value)").font(.title3.weight(.bold)).fontDesign(.rounded).monospacedDigit().foregroundStyle(Brand.ink)
                .contentTransition(.numericText())
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(fg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var pickups: some View {
        let today = Array(wordBook.metToday.prefix(3))
        if !today.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Today's pickups").font(.title3.weight(.semibold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                Spacer()
                if wordBook.metToday.count > 3 {
                    NavigationLink { WordsTab(session: session, wordBook: wordBook) } label: {
                        HStack(spacing: 4) { Text("\(wordBook.metToday.count)"); Image(systemName: "chevron.right") }.font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                            .accessibilityLabel("See all \(wordBook.metToday.count)")
                    }
                    .accessibilityIdentifier("see-all-words")
                }
            }
            HStack(spacing: 10) {
                ForEach(today) { p in
                    if let e = session.vocab.byId[p.id] {
                        Button { Speech.shared.say(e.kana); wordBook.recordHeard(e.id); detail = e } label: {
                            VStack(spacing: 6) {
                                Text(e.emoji.isEmpty ? "🌸" : e.emoji).font(.largeTitle)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                                    .background(Brand.mist, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text(e.kana).font(Brand.jp(16)).foregroundStyle(Brand.ink).lineLimit(1).minimumScaleFactor(0.6)
                                Text(session.vocab.shortMeaning(e)).font(.subheadline).foregroundStyle(Brand.ink).lineLimit(1)
                                // Seen in subtitles vs. actually studied (heard, revealed or answered).
                                // seen (subtitles only) → read (opened / heard) → practised (answered a check).
                                let practised = p.correct + p.wrong > 0
                                let studied = practised
                                Image(systemName: practised ? "checkmark.circle.fill" : p.timesHeard > 0 ? "book.fill" : "eye")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(studied ? Brand.success : Brand.violetDeep)
                            }
                            .brandCard(padding: 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(e.kana), \(e.meaning), \(p.correct + p.wrong > 0 ? "practised" : p.timesHeard > 0 ? "read" : "just seen")")
                        .accessibilityHint("Plays the word and opens its details")
                    }
                }
            }
        }
    }
}

// MARK: - World map

struct WorldView: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    @State private var selected: Place?
    @State private var open: Place?

    var body: some View {
        // The whole tall map (every landmark visible), scrollable, with the place card pinned below it.
        ScrollView {
            JourneyMap(journey: journey) { p in withAnimation(.snappy) { selected = p } }
                .aspectRatio(JourneyMap.tall.aspect, contentMode: .fit)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.bottom)
        .background(Brand.sky)
        .safeAreaInset(edge: .bottom) { sheet(selected ?? journey.currentPlace).padding(.horizontal, 16).padding(.bottom, 8) }
        .overlay(alignment: .top) {
            HStack {
                Label("\((LearningGoal(rawValue: session.settings.goal) ?? .culture).emoji) Your route", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.headline).foregroundStyle(Brand.ink)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.white.opacity(0.92), in: Capsule())
                Spacer()
                Label("\(wordBook.learnedCount)", systemImage: "character.book.closed.fill").font(.headline).foregroundStyle(Brand.violetDeep)
                    .accessibilityLabel("\(wordBook.learnedCount) words learned")
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.white.opacity(0.92), in: Capsule())
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(item: $open) { p in
            NavigationStack { PlaceView(place: p, session: session, wordBook: wordBook, journey: journey) }
        }
    }

    private func sheet(_ place: Place) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(place.scene).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(place.name).font(.headline).foregroundStyle(Brand.ink)
                        Text(place.japanese).font(Brand.jp(15)).foregroundStyle(Brand.ink)
                    }
                    HStack(spacing: 10) {
                        Label("\(journey.phrasesDone(place))/\(place.phrases.count)", systemImage: "text.bubble.fill")
                        Text(place.level)
                        if journey.state(place) == .locked { Image(systemName: "eye.fill").accessibilityLabel("Preview") }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                }
                Spacer(minLength: 0)
            }
            Button(journey.state(place) == .locked ? "Preview \(place.name)" : "Open \(place.name)") { open = place }.buttonStyle(.brandPrimary)
                .accessibilityIdentifier("open-place")
        }
        .brandCard(Brand.surface.opacity(0.96), padding: 16)
    }
}

// MARK: - Place

struct PlaceView: View {
    let place: Place
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [(phrase: Phrase, skill: Skill)]?
    @State private var quickMode = false

    private var wordsInPlace: (have: Int, total: Int) {
        let prev = place.index == 0 ? 0 : Curriculum.places[place.index - 1].wordsTarget
        let total = place.wordsTarget - prev
        return (min(total, max(0, wordBook.learnedCount - prev)), total)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(place.scene).resizable().scaledToFill().frame(height: 220).frame(maxWidth: .infinity).clipped()
                    .overlay(LinearGradient(colors: [.clear, Brand.sky], startPoint: .center, endPoint: .bottom))
                    .padding(.horizontal, -16)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(place.index) · \(place.level)", systemImage: "mappin.circle.fill").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Brand.violet, in: Capsule())
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(place.name).font(.largeTitle.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                        Text(place.japanese).font(Brand.jp(22)).foregroundStyle(Brand.ink)
                    }
                }
                .padding(.top, -50)
                HStack(spacing: 8) {
                    stat("\(journey.phrasesDone(place))/\(place.phrases.count)", "text.bubble.fill", "phrases", Brand.violetSoft, Brand.violetDeep)
                    stat("\(wordsInPlace.have)/\(wordsInPlace.total)", "character.book.closed.fill", "words", Brand.sunSoft, Brand.sunDeep)
                    stat("\(place.grammar.count)", "puzzlepiece.fill", "grammar", Skill.reading.soft, Skill.reading.color)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("Goals", systemImage: "flag.fill").font(.headline).foregroundStyle(Brand.ink)
                    ForEach(place.canDos) { c in
                        let done = journey.earned(c)
                        let some = c.phraseIds.contains { !journey.skills($0).isEmpty }
                        HStack(spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : some ? "circle.lefthalf.filled" : "circle")
                                .foregroundStyle(done ? Brand.success : some ? Brand.sun : Brand.ink).font(.title3)
                            Text(c.title).font(.callout).foregroundStyle(Brand.ink).opacity(done || some ? 1 : 0.6)
                            Spacer()
                            let phrases = c.phraseIds.compactMap { Curriculum.phraseById[$0] }
                            let dots = phrases.reduce(0) { $0 + journey.skills($1.id).count }
                            Text("\(dots)/\(phrases.count * 4)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Brand.violetDeep)
                                .accessibilityLabel("\(dots) of \(phrases.count * 4) practice dots")
                            if done { Text(c.stamp).font(Brand.jp(13)).foregroundStyle(Skill.speaking.color) }
                        }
                    }
                }
                .brandCard()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Phrases").font(.headline).foregroundStyle(Brand.ink); Spacer()
                        HStack(spacing: 6) { ForEach(Skill.allCases) { Image(systemName: $0.symbol).foregroundStyle($0.color) } }
                            .font(.subheadline).accessibilityLabel("read, hear, write, say")
                    }
                    ForEach(place.phrases) { p in
                        HStack(spacing: 8) {
                            Button {
                                let missing = Skill.allCases.filter { !journey.skills(p.id).contains($0) }
                                queue = (missing.isEmpty ? Skill.allCases : missing).map { (p, $0) }
                            } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        // Phrase on one line (never split mid-word), romaji under it.
                                        Text(p.pattern).font(Brand.jp(17)).foregroundStyle(Brand.ink)
                                            .lineLimit(1).minimumScaleFactor(0.7)
                                        if !p.pattern.contains("〜") && !p.pattern.contains("A ") {
                                            Text(Romanize.pronounced(p.pattern)).font(.subheadline).foregroundStyle(Brand.violetDeep)
                                        }
                                        Text(p.meaning).font(.subheadline).foregroundStyle(Brand.ink)
                                    }
                                    Spacer()
                                    CoverageDots(skills: journey.skills(p.id))
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { Speech.shared.say(p.exampleKana) } label: {
                                Image(systemName: "speaker.wave.2.fill").font(.footnote).foregroundStyle(Brand.violetDeep)
                                    .frame(width: 32, height: 32).background(Brand.violetSoft, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Hear \(p.meaning)")
                        }
                    }
                }
                .brandCard()
                // Only a short, readable sentence that really contains the phrase; with romaji. Otherwise no card.
                if let ex = place.phrases.lazy.compactMap({ p in Self.heardSentence(p, journey.examples[p.id] ?? []).map { (p, $0) } }).first {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Heard in your feed", systemImage: "ear.fill").font(.subheadline.weight(.bold)).foregroundStyle(Skill.listening.color)
                        Text(ex.1).font(Brand.jp(17)).foregroundStyle(Brand.ink)
                        Text(Romanize.pronounced(ex.1)).font(.subheadline).foregroundStyle(Skill.listening.color)
                    }
                    .brandCard(Skill.listening.soft)
                }
                let gaps = journey.gaps(place).flatMap { g in g.missing.map { (g.phrase, $0) } }
                Button(gaps.isEmpty ? "Place complete ✓" : "Fill my \(gaps.count) gaps") {
                    queue = gaps.map { (phrase: $0.0, skill: $0.1) }
                }
                .buttonStyle(.brandPrimary)
                .disabled(gaps.isEmpty)
                .accessibilityIdentifier("fill-gaps")
                if gaps.count > 6 {
                    // Spare minutes: 6 steps, a different phrase each time (round-robin), about 2–3 minutes.
                    Button {
                        // No speaking steps when the mic isn't available, so the set is exactly 6 doable steps.
                        let canSpeak = !SpeechCheck.permissionDenied
                        var byPhrase = journey.gaps(place).map { (phrase: $0.phrase, missing: canSpeak ? $0.missing : $0.missing.filter { $0 != .speaking }) }
                        var quick: [(phrase: Phrase, skill: Skill)] = []
                        while quick.count < 6, byPhrase.contains(where: { !$0.missing.isEmpty }) {
                            for k in byPhrase.indices where quick.count < 6 && !byPhrase[k].missing.isEmpty {
                                quick.append((phrase: byPhrase[k].phrase, skill: byPhrase[k].missing.removeFirst()))
                            }
                        }
                        queue = quick
                        quickMode = true
                    } label: { Label("Quick set · 6", systemImage: "bolt.fill") }
                    .buttonStyle(.brandQuiet)
                    .accessibilityIdentifier("quick-gaps")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Brand.sky.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .fullScreenCover(isPresented: Binding(get: { queue != nil }, set: { if !$0 { queue = nil } })) {
            PracticeQueue(items: queue ?? [], place: place, journey: journey, allowRetries: !quickMode)
                .onDisappear { quickMode = false }
        }
    }

    /// The sentence (split at 。！？) that contains the phrase, if it's short enough for a beginner (≤ 24 chars).
    static func heardSentence(_ p: Phrase, _ lines: [String]) -> String? {
        for line in lines {
            var cur = ""
            for ch in line {
                cur.append(ch)
                if "。？！?!".contains(ch) {
                    let t = cur.trimmingCharacters(in: .whitespaces)
                    if p.appears(in: t), t.count <= 24 { return t }
                    cur = ""
                }
            }
            let t = cur.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, p.appears(in: t), t.count <= 24 { return t }
        }
        return nil
    }

    private func stat(_ n: String, _ symbol: String, _ l: String, _ bg: Color, _ fg: Color) -> some View {
        Label(n, systemImage: symbol).font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(fg)
            .accessibilityLabel("\(n) \(l)")
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension HomeView {
    /// Persistent proof the good-stop gift happened (stays on Home for the rest of the day).
    var giftCard: some View {
        let g = JourneyStore.gift(journey.goodStops)
        return HStack(spacing: 14) {
            MascotImage(mood: .gift, size: 64)
                .overlay(alignment: .bottomTrailing) { Text(g.emoji).font(.title3) }
            VStack(alignment: .leading, spacing: 3) {
                Text("Good stop! \(g.name)").font(.headline).foregroundStyle(Brand.ink)
                Label(journey.goodStops >= 3 ? "🌸" : "\(journey.goodStops)/3 🌸", systemImage: "gift.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.sunDeep)
            }
            Spacer(minLength: 0)
        }
        .brandCard(Brand.sunSoft.opacity(0.6), padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gift-card")
    }
}

/// A pickup's details: how to say it, what it means, where you met it and its learning status.
struct WordDetailSheet: View {
    let entry: VocabEntry
    let progress: WordProgress?
    let level: ScriptLevel
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                        .frame(width: 32, height: 32).background(Brand.mist, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close")
            }
            .padding(.bottom, -10)
            HStack(alignment: .center, spacing: 14) {
                Text(entry.emoji.isEmpty ? "🌸" : entry.emoji).font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.written).font(Brand.jp(30, bold: true)).foregroundStyle(Brand.ink)
                    Text("\(entry.kana) · \(entry.romaji)").font(.subheadline).foregroundStyle(Brand.violetDeep)
                }
                Spacer()
                Button { Speech.shared.say(entry.kana) } label: {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Brand.violetDeep)
                        .frame(width: 48, height: 48).background(Brand.violetSoft, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel("Hear it")
            }
            Text(entry.meaning).font(.title3.weight(.semibold)).foregroundStyle(Brand.ink)
            if let c = progress?.contexts.last, !c.line.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label(c.title.isEmpty ? "a Short" : c.title, systemImage: "play.rectangle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep).lineLimit(1)
                    Text("“\(c.line)”").font(.callout).foregroundStyle(Brand.ink)
                }
            }
            if let ex = SimpleExample.make(for: entry) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Example", systemImage: "text.bubble.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                    Text(ex.ja).font(Brand.jp(17)).foregroundStyle(Brand.ink)
                    Text("\(ex.romaji) · \(ex.en)").font(.subheadline).foregroundStyle(Brand.ink)
                }
                .onTapGesture { Speech.shared.say(ex.ja) }
            }
            if let p = progress {
                HStack(spacing: 12) {
                    Image(systemName: p.isLearned ? "checkmark.seal.fill" : "hourglass").accessibilityLabel(p.isLearned ? "Learned" : "Not learned yet")
                    Label("\(p.timesSeen)×", systemImage: "eye.fill").accessibilityLabel("Met \(p.timesSeen) times")
                    Label(p.due.formatted(.relative(presentation: .named)), systemImage: "clock.fill").accessibilityLabel("Next check \(p.due.formatted(.relative(presentation: .named)))")
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(p.isLearned ? Brand.success : Brand.sunDeep)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Brand.surface.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .accessibilityIdentifier("word-detail")
    }
}

extension HomeView {
    func iconCount(_ symbol: String, _ n: Int, _ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundStyle(color)
            Text("\(n)").fontDesign(.rounded).monospacedDigit().foregroundStyle(Brand.ink)
        }
        .font(.subheadline.weight(.bold))
        .accessibilityLabel(label)
    }
}

extension HomeView {
    /// One insight at a time (icon + one line); tap for the next.
    @ViewBuilder var insightCard: some View {
        let all = Insights.compute(wordBook: wordBook, journey: journey, vocab: session.vocab, level: session.settings.jlptLevel)
        if !all.isEmpty {
            let i = all[insightIndex % all.count]
            Button { withAnimation(.snappy) { insightIndex += 1 } } label: {
                HStack(spacing: 12) {
                    MascotImage(mood: .idea, size: 48)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: i.symbol).font(.caption2.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Brand.violet, in: Circle())
                                .symbolEffect(.bounce, value: insightIndex)
                        }
                    Text(i.text).font(.subheadline).foregroundStyle(Brand.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if all.count > 1 { Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Brand.ink3) }
                }
                .brandCard(padding: 12)
                .id(i.id)
                .transition(.opacity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Insight: \(i.text)")
            .accessibilityHint(all.count > 1 ? "Shows the next insight" : "")
            .accessibilityIdentifier("insight-card")
        }
    }
}
