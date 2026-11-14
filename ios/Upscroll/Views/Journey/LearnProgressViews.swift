import SwiftUI

// MARK: - Learn

struct LearnView: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    @State private var queue: [(phrase: Phrase, skill: Skill)]?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let place = journey.currentPlace
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Learn").font(.largeTitle.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                // Daily review first: it's the main action on most visits.
                if let summary = wordBook.freshReviewSummary {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.success)
                        Text("Nice stop. \(summary).").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                        Spacer(minLength: 0)
                        Button { wordBook.lastReviewSummary = nil } label: { Image(systemName: "xmark").foregroundStyle(Brand.ink3) }
                            .buttonStyle(.plain).accessibilityLabel("Dismiss")
                    }
                    .brandCard(Brand.successSoft, padding: 12)
                    .accessibilityIdentifier("review-summary")
                }
                NavigationLink {
                    ReviewTab(session: session, wordBook: wordBook)
                } label: {
                    HStack(spacing: 12) {
                        MascotImage(mood: .sleepy, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wordBook.dueWords.isEmpty ? "No sleepy words" : "\(wordBook.dueWords.count) word\(wordBook.dueWords.count == 1 ? " is" : "s are") getting sleepy")
                                .font(.headline).foregroundStyle(Brand.ink)
                            if !wordBook.dueWords.isEmpty {
                                Label("1 min", systemImage: "timer").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Brand.ink3)
                    }
                    .brandCard(Brand.cream, padding: 12)
                }
                .buttonStyle(.plain)
                HStack(spacing: 12) {
                    MascotImage(mood: .map, size: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(journey.gapCount(place)) gaps in \(place.name)").font(.headline).foregroundStyle(Brand.violetDeep)
                        if journey.gapCount(place) > 0, journey.gapCount(place) == journey.gapCount(place, skill: .speaking), SpeechCheck.permissionDenied {
                            Label("Mic off", systemImage: "mic.slash.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.warn)
                        }
                    }
                }
                .brandCard(Brand.violetSoft, padding: 12)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(Skill.allCases) { s in
                        Button { start(skill: s, place: place) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: s.symbol).foregroundStyle(s.color)
                                    .frame(width: 36, height: 36).background(.white, in: RoundedRectangle(cornerRadius: 12))
                                Text(s.title).font(.headline).fontDesign(.rounded).foregroundStyle(Brand.ink)
                                Label("\(journey.gapCount(place, skill: s))", systemImage: "circle.dotted").font(.subheadline.weight(.semibold)).foregroundStyle(s.color)
                                    .accessibilityLabel("\(journey.gapCount(place, skill: s)) gaps")
                            }
                            .brandCard(s.soft, padding: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("learn-\(s.rawValue)")
                    }
                }

                // Mixed check: phrases you've already practised, shuffled, one hidden-answer task each
                // (listening or building, never right after seeing the answer). Tests what you can recall unaided.
                let practised = Curriculum.allPhrases.filter { !journey.skills($0.id).isEmpty }
                if practised.count >= 3 {
                    Button {
                        queue = practised.shuffled().prefix(5).map { p in (phrase: p, skill: [Skill.listening, .writing].randomElement()!) }
                    } label: {
                        Label("Mixed check · \(min(5, practised.count)) phrases, no hints", systemImage: "shuffle")
                    }
                    .buttonStyle(.brandSecondary)
                    .accessibilityIdentifier("mixed-check")
                }

                Button {
                    let q = place.phrases.first.map { $0.example } ?? "日本語"
                    // Aim at learner videos (やさしい日本語 = easy Japanese, 初心者 = beginners), not any clip whose title matches.
                    let query = "\(q) やさしい日本語 初心者 shorts"
                    let url = URL(string: "https://m.youtube.com/results?search_query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
                    session.web.open(url)
                    dismiss()   // show the search results right away instead of leaving them behind the sheet
                } label: {
                    Label("Find real Japanese Shorts that say \(place.phrases.first?.example ?? "it")", systemImage: "magnifyingglass")
                }
                .buttonStyle(.brandSecondary)
                .accessibilityHint("Closes this screen and opens YouTube search results. Use the Shorts button to return to your feed.")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Quests").font(.title3.weight(.semibold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                }
                ForEach(place.canDos) { c in
                    Button {
                        queue = c.phraseIds.compactMap { Curriculum.phraseById[$0] }.flatMap { p in
                            Skill.allCases.filter { !journey.skills(p.id).contains($0) }.map { (phrase: p, skill: $0) }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(c.stamp).font(Brand.jp(15, bold: true)).foregroundStyle(journey.earned(c) ? .white : Skill.speaking.color)
                                .frame(width: 52, height: 52)
                                .background(journey.earned(c) ? Skill.speaking.color : Skill.speaking.soft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.headline).foregroundStyle(Brand.ink)
                            }
                            Spacer()
                            Image(systemName: journey.earned(c) ? "checkmark.seal.fill" : "chevron.right")
                                .foregroundStyle(journey.earned(c) ? Brand.success : Brand.ink3)
                        }
                        .brandCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding(16)
        }
        .background(Brand.sky.ignoresSafeArea())
        .fullScreenCover(isPresented: Binding(get: { queue != nil }, set: { if !$0 { queue = nil } })) {
            PracticeQueue(items: queue ?? [], place: place, journey: journey)
        }
    }

    private func start(skill: Skill, place: Place) {
        let missing = journey.gaps(place).filter { $0.missing.contains(skill) }.map { (phrase: $0.phrase, skill: skill) }
        queue = missing.isEmpty ? place.phrases.prefix(3).map { (phrase: $0, skill: skill) } : missing
    }
}

// MARK: - Progress (Words · Impact · Rewards)

struct JourneyProgressView: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    enum Section: String, CaseIterable { case words = "Words", impact = "Impact", rewards = "Rewards" }
    @State private var section: Section = .words
    @State private var showFeedSheet = false
    @State private var showShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("My Journey").font(.largeTitle.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                switch section {
                case .words: words
                case .impact: impact
                case .rewards: rewards
                }
            }
            .padding(16)
            .padding(.bottom, 60)   // last card clears the tab bar
        }
        .background(Brand.sky.ignoresSafeArea())
        .sheet(isPresented: $showFeedSheet) { JapaneseFeedSheet(session: session, journey: journey) }
        .sheet(isPresented: $showShare) { ShareCardSheet(journey: journey, wordBook: wordBook) }
    }

    // Words
    private var words: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(wordBook.learnedCount)").font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(Brand.violetDeep)
                    Text("words learned").font(.headline).foregroundStyle(Brand.ink)
                    Label("\(wordBook.words.count) met", systemImage: "eye.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink).padding(.top, 2)
                }
                Spacer()
                MascotImage(mood: .cheer, size: 96)
            }
            .brandCard()
            LadderCard(wordsLearned: wordBook.learnedCount, dailyGoal: session.settings.dailyGoal)
            VStack(alignment: .leading, spacing: 10) {
                Text("By level").font(.headline).foregroundStyle(Brand.ink)
                ForEach(JLPT.levels.prefix(3), id: \.self) { lv in
                    let n = wordBook.learnedCount(level: lv, vocab: session.vocab), total = session.vocab.countByLevel[lv] ?? 1
                    HStack(spacing: 10) {
                        Text("N\(lv)").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                        ProgressBar(value: Double(n) / Double(total), color: lv == 5 ? Brand.violet : lv == 4 ? Skill.reading.color : Skill.listening.color)
                        Text("\(n)/\(total)").font(.subheadline).foregroundStyle(Brand.ink).monospacedDigit()
                    }
                }
            }
            .brandCard()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Japanese in your feed").font(.headline); Spacer(); Text("\(Int(journey.japaneseFeedShare * 100))%").font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Skill.listening.color) }
                ProgressBar(value: journey.japaneseFeedShare, color: Skill.listening.color)
                Button { showFeedSheet = true } label: { Label("More Japanese", systemImage: "plus.circle.fill") }.buttonStyle(.brandSecondary)
                    .accessibilityIdentifier("japanese-feed")
            }
            .brandCard(Skill.listening.soft)
            NavigationLink { WordsTab(session: session, wordBook: wordBook) } label: {
                HStack { Label("All my words", systemImage: "character.book.closed.fill.ja"); Spacer(); Image(systemName: "chevron.right") }
                    .font(.headline).foregroundStyle(Brand.ink).brandCard(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }

    // Impact
    private var impact: some View {
        let w = journey.total(lastDays: 7)
        let share = w.scrollSeconds > 0 ? min(w.japaneseSeconds, w.scrollSeconds) / w.scrollSeconds : 0
        let all = journey.allTime
        let shares = journey.weeklyShare()
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack { Ring(value: share).frame(width: 96, height: 96); Text("\(Int(share * 100))%").font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.violetDeep) }
                    VStack(alignment: .leading, spacing: 2) {
                        Label("This week", systemImage: "calendar").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                        Text("\(durationText(w.scrollSeconds)) → \(durationText(min(w.japaneseSeconds, w.scrollSeconds))) 🇯🇵")
                            .font(.headline).foregroundStyle(Brand.ink)
                        // Two different things: Japanese you saw (words, cards) vs Japanese you heard.
                        let heard = min(w.audioSeconds ?? 0, w.scrollSeconds)
                        HStack(spacing: 12) {
                            Label(durationText(max(0, min(w.japaneseSeconds, w.scrollSeconds) - heard)), systemImage: "eye.fill")
                                .accessibilityLabel("Seen: \(durationText(max(0, min(w.japaneseSeconds, w.scrollSeconds) - heard)))")
                            Label(durationText(heard), systemImage: "ear.fill")
                                .accessibilityLabel("Heard: \(durationText(heard))")
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                    }
                }
                HStack(spacing: 8) {
                    chip("\(w.linesHeard)", "waveform", Skill.listening, "lines heard")
                    chip("\(journey.stamps.count)", "seal.fill", .writing, "can-dos")
                    chip("\(w.goodStops)", "hand.raised.fill", .speaking, "good stops")
                }
            }
            .brandCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("impact-week")
            VStack(alignment: .leading, spacing: 10) {
                Text("Learning share, week by week").font(.headline).foregroundStyle(Brand.ink)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(shares.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 4) {
                            Text("\(Int(v * 100))%").font(.caption.weight(.semibold)).foregroundStyle(i == shares.count - 1 ? Brand.violetDeep : Brand.ink)
                            RoundedRectangle(cornerRadius: 8).fill(i == shares.count - 1 ? Brand.violet : Brand.violetSoft)
                                .frame(height: max(8, 140 * v))
                            Text(i == shares.count - 1 ? "now" : "\(shares.count - 1 - i)w").font(.caption.weight(.semibold)).foregroundStyle(Brand.ink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 180, alignment: .bottom)
            }
            .brandCard()
            VStack(alignment: .leading, spacing: 8) {
                Text("Since you started").font(.headline).foregroundStyle(Brand.ink)
                ladder("play.rectangle.fill", durationText(all.scrollSeconds), "scrolled", first: true)
                ladder("eye.fill", durationText(all.japaneseSeconds), "Japanese")
                ladder("ear.fill", durationText(all.audioSeconds ?? 0), "heard")
                ladder("character.book.closed.fill", "\(wordBook.learnedCount)", "words")
                ladder("seal.fill", "\(journey.stamps.count)", "can-dos")
                ladder("mappin.circle.fill", "\(journey.souvenirs.count)", "places")
            }
            .brandCard(Brand.cream)
            Button { showShare = true } label: { Label("Share my week", systemImage: "square.and.arrow.up") }
                .buttonStyle(.brandPrimary)
        }
    }

    // Rewards
    /// Rewards you can spend: what each does and how to earn the next.
    private var usableRewards: some View {
        let r = Rewards.shared
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                MascotImage(mood: .freeze, size: 64)
                Text("Rewards").font(.headline).foregroundStyle(Brand.ink)
            }
            HStack(spacing: 14) {
                inventoryTile(RewardIcon.freeze.symbol, r.freezes, Rewards.maxFreezes, RewardIcon.freeze.color, "Streak freeze")
                inventoryTile(RewardIcon.skip.symbol, r.skips, Rewards.maxSkips, RewardIcon.skip.color, "Skip ticket")
            }
            HStack(spacing: 8) {
                Image(systemName: RewardIcon.skip.symbol).foregroundStyle(RewardIcon.skip.color)
                ProgressBar(value: r.progressToSkip, height: 8)
                let left = Rewards.correctPerSkip - Int((r.progressToSkip * Double(Rewards.correctPerSkip)).rounded())
                Label("\(left)", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Brand.success)
                    .accessibilityLabel("\(left) more right answers for a skip ticket")
            }
            HStack(spacing: 6) {
                Image(systemName: RewardIcon.freeze.symbol).foregroundStyle(RewardIcon.freeze.color)
                Label("7 · 30 · 100", systemImage: "flame.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.sunDeep)
                    .accessibilityLabel("Earn a freeze with a good stop or a 7, 30 or 100-day streak")
            }
        }
        .brandCard()
        .accessibilityIdentifier("usable-rewards")
    }

    private func inventoryTile(_ symbol: String, _ n: Int, _ max: Int, _ color: Color, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.title2).foregroundStyle(color)
                    .symbolEffect(.bounce, value: n)
                Text("\(n)/\(max)").font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
            }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Brand.mist, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private var rewards: some View {
        VStack(alignment: .leading, spacing: 14) {
            usableRewards
            // Gifts first: the latest reward is visible without scrolling past the tab bar.
            HStack(spacing: 12) {
                MascotImage(mood: .cheer, size: 56)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(journey.goodStops) good stops").font(.headline).foregroundStyle(Brand.violetDeep)
                    if journey.goodStops > 0 {
                        Text("\(JourneyStore.gift(journey.goodStops).emoji) \(JourneyStore.gift(journey.goodStops).name)\(journey.goodStops >= 3 ? " · 🌸" : "")")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                    }
                }
            }
            .brandCard(Brand.violetSoft, padding: 12)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    MascotImage(mood: .map, size: 56)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Backpack").font(.headline).foregroundStyle(Brand.ink)
                        Label("\(journey.souvenirs.count)/\(Curriculum.places.count)", systemImage: "bag.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Curriculum.places) { p in
                        let st = journey.state(p)
                        VStack(spacing: 2) {
                            Image(p.souvenir).resizable().scaledToFit().frame(height: 56).opacity(st == .locked ? 0.28 : 1)
                            Text(p.name).font(.caption.weight(.semibold)).foregroundStyle(Brand.ink).opacity(st == .locked ? 0.5 : 1).lineLimit(1).minimumScaleFactor(0.7)
                            Group {
                                if st == .done { Image(systemName: "checkmark.seal.fill").foregroundStyle(Brand.sunDeep) }
                                else if st == .current { Text("\(journey.phrasesDone(p))/\(p.phrases.count)").font(.caption.weight(.semibold)).foregroundStyle(Brand.violetDeep) }
                                else { Image(systemName: "lock.fill").foregroundStyle(Brand.ink).opacity(0.5) }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(st == .done ? Brand.sunSoft : st == .current ? Brand.violetSoft : Brand.mist, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .brandCard()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Passport stamps").font(.headline); Spacer(); Label("\(journey.stamps.count)", systemImage: "seal.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Skill.speaking.color) }
                let visible = Curriculum.places.filter { journey.state($0) != .locked }.flatMap(\.canDos)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(visible) { c in
                        let on = journey.earned(c)
                        VStack(spacing: 4) {
                            Text(c.stamp).font(Brand.jp(c.stamp.count > 2 ? 11 : 16, bold: true)).foregroundStyle(on ? Brand.ink : Brand.ink3)
                                .frame(width: 62, height: 62)
                                .background(on ? Skill.speaking.soft : .clear, in: Circle())
                                .overlay(Circle().strokeBorder(on ? Skill.speaking.color : Brand.line, style: StrokeStyle(lineWidth: 3, dash: on ? [4, 3] : [2, 4])))
                                .rotationEffect(.degrees(on ? -6 : 0))
                            Text(c.title).font(.caption).foregroundStyle(Brand.ink).opacity(on ? 1 : 0.5).multilineTextAlignment(.center).lineLimit(2)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(c.title), \(on ? "earned" : "not yet")")
                    }
                }
            }
            .brandCard()
            VStack(alignment: .leading, spacing: 10) {
                Text("Word badges").font(.headline)
                HStack(spacing: 8) {
                    ForEach(Curriculum.wordBadges, id: \.self) { n in
                        let on = wordBook.learnedCount >= n
                        Text(n >= 1000 ? "\(Double(n) / 1000, specifier: "%g")k" : "\(n)").font(.headline).fontDesign(.rounded)
                            .foregroundStyle(on ? Brand.ink : Brand.ink3)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Brand.sun : .white, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .brandCard(Brand.cream)
        }
    }

    private func chip(_ t: String, _ symbol: String, _ s: Skill, _ what: String) -> some View {
        Label(t, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(s.color)
            .padding(.horizontal, 10).padding(.vertical, 6).background(s.soft, in: Capsule())
            .accessibilityLabel("\(t) \(what)")
    }

    private func ladder(_ symbol: String, _ n: String, _ l: String, first: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(first ? Brand.ink : Brand.violet).frame(width: 24)
            Text(n).font(.headline).fontDesign(.rounded).foregroundStyle(first ? Brand.ink : Brand.violetDeep).frame(width: 90, alignment: .leading)
            Text(l).font(.callout).foregroundStyle(Brand.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Session recap

struct SessionRecapView: View {
    @State private var showHowWeCount = false
    @ObservedObject var journey: JourneyStore
    @ObservedObject var wordBook: WordBook
    var reachedLimit: Bool
    /// Daily scroll limit in minutes (0 = off); the limit is per day, not per session.
    var dailyLimitMinutes: Int = 0
    var vocab: VocabStore? = nil
    var level: Int = 5
    var onGoodStop: () -> Void
    var onKeepScrolling: () -> Void

    var body: some View {
        let s = journey.session
        let share = s.scrollSeconds > 0 ? s.japaneseSeconds / s.scrollSeconds : 0
        let newStamps = journey.stamps.filter { !s.stampsAtStart.contains($0.id) }
        let place = journey.currentPlace
        ScrollView {
            VStack(spacing: 14) {
                MascotImage(mood: .cheer, size: 120)
                Text(reachedLimit ? "You reached today's limit" : "Nice session!").font(.largeTitle.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                if dailyLimitMinutes > 0 {
                    // Daily total vs. limit, kept apart from this session's numbers below.
                    let todayMin = Int(journey.today.scrollSeconds / 60)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Today", systemImage: "sun.max.fill").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                            Spacer()
                            Label("\(todayMin)/\(dailyLimitMinutes) min", systemImage: "hourglass").font(.subheadline.weight(.bold)).foregroundStyle(reachedLimit ? Brand.warn : Brand.ink)
                        }
                        ProgressBar(value: min(1, Double(todayMin) / Double(dailyLimitMinutes)), height: 8)
                    }
                    .brandCard(padding: 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("recap-daily-limit")
                }
                Label("This session", systemImage: "play.rectangle.fill").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Label(durationText(s.scrollSeconds), systemImage: "play.rectangle.fill").font(.title.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                        Image(systemName: "arrow.right").font(.title2.weight(.bold)).foregroundStyle(Brand.ink)
                        Text("\(durationText(s.japaneseSeconds)) 🇯🇵").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Brand.violetDeep)
                    }
                    ProgressBar(value: share, height: 14)
                    Text("\(Int(share * 100))%").font(.headline).foregroundStyle(Brand.success)
                }
                .brandCard()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recap-conversion")
                // Three kinds of progress, kept apart so each number means one thing.
                let seen = wordBook.words.values.filter { $0.lastSeen >= s.start }.count
                let newW = wordBook.newWords(since: s.start)
                VStack(spacing: 8) {
                    progressRow("eye.fill", "Words seen", "\(seen) · +\(newW) new", Brand.sunDeep, Brand.sunSoft)
                    progressRow("ear.fill", "Lines heard", "\(s.linesHeard)", Skill.listening.color, Skill.listening.soft)
                    progressRow("pencil.and.list.clipboard", "Practice", "\(durationText(s.practiceSeconds)) · +\(journey.totalDots - s.dotsAtStart) ●", Skill.speaking.color, Skill.speaking.soft)
                    progressRow("checkmark.seal.fill", "Learned", "\(wordBook.learnedCount)", Brand.success, Brand.successSoft)
                }
                .accessibilityIdentifier("recap-progress-kinds")
                // What the numbers mean: one ⓘ tap away instead of a block of text.
                Button { withAnimation(.snappy) { showHowWeCount.toggle() } } label: {
                    Label(showHowWeCount ? "Hide" : "How we count", systemImage: showHowWeCount ? "xmark.circle.fill" : "info.circle")
                        .labelStyle(.iconOnly).font(.title3).foregroundStyle(Brand.violetDeep)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                if showHowWeCount {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Japanese word, card or audio on screen", systemImage: "play.rectangle.fill")
                    Label("Japanese words in your subtitles", systemImage: "eye.fill")
                    Label("Japanese lines heard to the end", systemImage: "ear.fill")
                    Label("Practice answered right", systemImage: "circle.fill")
                    Label("Right in a check, lasts 3+ days", systemImage: "checkmark.seal.fill")
                }
                .font(.subheadline).foregroundStyle(Brand.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .brandCard(padding: 12)
                .accessibilityIdentifier("recap-how-we-count")
                }
                if let vocab, let i = Insights.compute(wordBook: wordBook, journey: journey, vocab: vocab, level: level).first {
                    Label(i.text, systemImage: i.symbol).font(.subheadline).foregroundStyle(Brand.violetDeep)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brandCard(Brand.violetSoft, padding: 12)
                        .accessibilityIdentifier("recap-insight")
                }
                ForEach(newStamps) { c in
                    HStack(spacing: 14) {
                        Text(c.stamp).font(Brand.jp(16, bold: true)).foregroundStyle(Skill.speaking.color)
                            .frame(width: 62, height: 62).background(Skill.speaking.soft, in: Circle())
                            .overlay(Circle().strokeBorder(Skill.speaking.color, style: StrokeStyle(lineWidth: 3, dash: [4, 3]))).rotationEffect(.degrees(-8))
                        VStack(alignment: .leading, spacing: 1) {
                            Label("New stamp", systemImage: "seal.fill").font(.subheadline.weight(.bold)).foregroundStyle(Skill.speaking.color)
                            Text(c.title).font(.headline).foregroundStyle(Brand.ink)
                        }
                        Spacer()
                    }
                    .brandCard(padding: 12)
                }
                HStack(spacing: 12) {
                    Image(place.souvenir).resizable().scaledToFit().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(place.name) · \(journey.phrasesDone(place))/\(place.phrases.count)", systemImage: "text.bubble.fill").font(.headline).foregroundStyle(Brand.violetDeep)
                        ProgressBar(value: Double(journey.phrasesDone(place)) / Double(place.phrases.count), height: 8, track: .white)
                    }
                }
                .brandCard(Brand.violetSoft, padding: 12)
                Button(action: onGoodStop) {
                    // Rewards shown with the app's icons, in the button's own text color.
                    Label { Text("Good stop · ") + RewardIcon.gift.text(tinted: false) + Text(" ") + RewardIcon.freeze.text(tinted: false) }
                        icon: { Image(systemName: "sun.max.fill") }
                        .accessibilityLabel("Good stop: get a gift and a streak freeze")
                }
                .buttonStyle(.brandPrimary)
                    .accessibilityIdentifier("good-stop")
                Button(action: onKeepScrolling) { Label("Keep scrolling", systemImage: "play.fill") }.buttonStyle(.brandQuiet)
                    .accessibilityIdentifier("recap-keep")
            }
            .padding(16)
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) { Brand.sky; Image("scene_sky").resizable().scaledToFill().frame(height: 320).clipped() }.ignoresSafeArea()
        }
    }

    private func progressRow(_ icon: String, _ title: String, _ value: String, _ fg: Color, _ bg: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.headline).foregroundStyle(fg)
                .frame(width: 36, height: 36).background(bg, in: Circle())
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Brand.ink)
            Spacer()
            Text(value).font(.subheadline.weight(.bold)).fontDesign(.rounded).foregroundStyle(fg).multilineTextAlignment(.trailing)
        }
        .brandCard(padding: 10)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ n: String, _ l: String, _ bg: Color, _ fg: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).font(.title.weight(.bold)).fontDesign(.rounded).foregroundStyle(fg)
            Text(l).font(.subheadline).foregroundStyle(Brand.ink)
        }
        .brandCard(bg, padding: 14)
    }
}

// MARK: - Japanese feed guide

struct JapaneseFeedSheet: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var journey: JourneyStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MascotImage(mood: .map, size: 110)
                Text("More Japanese Shorts").font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                Label("\(Int(journey.japaneseFeedShare * 100))% · 7 days", systemImage: "ear.fill").font(.headline).foregroundStyle(Skill.listening.color)
                    .accessibilityLabel("Japanese audio in your feed: \(Int(journey.japaneseFeedShare * 100))% over the last 7 days")
                step("1", "globe.asia.australia.fill", "Japanese YouTube",
                     done: session.settings.japaneseFeed, action: session.settings.japaneseFeed ? "Off" : "On") {
                    // Easy to undo: the same button switches back to the normal feed.
                    session.settings.japaneseFeed.toggle()
                    session.web.open(WebController.feedURL(japanese: session.settings.japaneseFeed))
                }
                step("2", "character.ja", "Add 日本語 to Google",
                     done: journey.feedSteps.contains("language"), action: "Open") {
                    journey.feedSteps.insert("language")
                    session.web.open(URL(string: "https://myaccount.google.com/language")!)
                    dismiss()
                }
                step("3", "person.3.fill", "Follow 3 creators",
                     done: journey.feedSteps.contains("creators"), action: "Search") {
                    journey.feedSteps.insert("creators")
                    session.web.open(URL(string: "https://m.youtube.com/results?search_query=%E3%82%84%E3%81%95%E3%81%97%E3%81%84%E6%97%A5%E6%9C%AC%E8%AA%9E+shorts")!)
                    dismiss()
                }
                Button { dismiss() } label: { Label("Later", systemImage: "clock") }.buttonStyle(.brandQuiet)
            }
            .padding(20)
        }
        .background(Brand.surface.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func step(_ n: String, _ symbol: String, _ t: String, done: Bool, action: String, run: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark" : "\(n).circle").font(.headline).foregroundStyle(done ? .white : Brand.violetDeep)
                .frame(width: 36, height: 36).background(done ? Brand.success : .white, in: Circle())
            Label(t, systemImage: symbol).font(.headline).foregroundStyle(Brand.ink)
            Spacer()
            Button(action, action: run).font(.subheadline.weight(.bold)).foregroundStyle(Brand.violetDeep)
                .padding(.horizontal, 12).padding(.vertical, 8).background(Brand.violetSoft, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(14)
        .background(done ? Brand.mist : Brand.violetSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Share card

struct ImpactCard: View {
    let scroll: Double, japanese: Double, learned: Int, canDos: Int
    var body: some View {
        let share = scroll > 0 ? japanese / scroll : 0
        VStack(spacing: 12) {
            ZStack {
                Image("scene_sky").resizable().scaledToFill().frame(height: 150).clipped()
                MascotImage(mood: .cheer, size: 120)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            Label("This week", systemImage: "calendar").font(.subheadline.weight(.bold)).foregroundStyle(Brand.violetDeep)
            HStack(spacing: 10) {
                Label(durationText(scroll), systemImage: "play.rectangle.fill").font(.title2.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                Image(systemName: "arrow.right").foregroundStyle(Brand.ink)
                Text("\(durationText(japanese)) 🇯🇵").font(.title.weight(.heavy)).fontDesign(.rounded).foregroundStyle(Brand.violetDeep)
            }
            HStack(spacing: 8) {
                box("\(learned)", "character.book.closed.fill", Brand.sunSoft, Brand.sunDeep)
                box("\(canDos)", "seal.fill", Brand.successSoft, Brand.success)
                box("\(Int(share * 100))%", "sparkles", Brand.violetSoft, Brand.violetDeep)
            }
            HStack(spacing: 6) {
                Text("Upscroll").font(.headline).foregroundStyle(Brand.violetDeep)
                Text("🇯🇵").font(.headline)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Brand.sky, in: RoundedRectangle(cornerRadius: 30))
    }
    private func box(_ n: String, _ symbol: String, _ bg: Color, _ fg: Color) -> some View {
        Label(n, systemImage: symbol).font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 10).background(bg, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ShareCardSheet: View {
    @ObservedObject var journey: JourneyStore
    @ObservedObject var wordBook: WordBook
    @State private var image: Image?

    var body: some View {
        let w = journey.total(lastDays: 7)
        let card = ImpactCard(scroll: w.scrollSeconds, japanese: w.japaneseSeconds, learned: wordBook.learnedCount, canDos: journey.stamps.count)
        VStack(spacing: 18) {
            // Shadow on the card's shape only (the card is opaque), never on its text.
            card.background(RoundedRectangle(cornerRadius: 30).fill(Brand.sky)
                .shadow(color: .black.opacity(0.15), radius: 20, y: 10))
            if let image {
                ShareLink(item: image, preview: SharePreview("My week in Japanese", image: image)) {
                    Label("Share my week", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.brandPrimary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.ink.opacity(0.9).ignoresSafeArea())
        .onAppear {
            let r = ImageRenderer(content: card)
            r.scale = 3
            if let ui = r.uiImage { image = Image(uiImage: ui) }
        }
    }
}
