import SwiftUI

@main
struct UpscrollApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // Tapped the link in the sign-in email.
                .onOpenURL { url in Task { await SupabaseAuth.shared.handleCallback(url) } }
        }
    }
}

struct RootView: View {
    @StateObject private var wordBook: WordBook
    @StateObject private var journey: JourneyStore
    @StateObject private var session: FeedSession
    @State private var showDashboard = false
    @State private var showRecap = false
    @State private var showLab = false
    @State private var showGuide = false
    @State private var showFeedSheet = false
    @ObservedObject private var rewards = Rewards.shared
    @AppStorage("feedChipDismissedDay") private var feedChipDismissedDay = ""
    /// "8 words met today" shows briefly when the count changes, then fades to just あ + number (it covered video text).
    @AppStorage("seenHowItWorks.v1") private var seenGuide = false
    @AppStorage("onboarded.v1") private var onboarded = false
    private let bridge: PlatformBridge = YouTubeShortsBridge()

    init() {
        Plan.startTrialIfNeeded()   // the 30-day Premium trial starts on first open, no account needed
        let wb = WordBook()
        let j = JourneyStore()
        _wordBook = StateObject(wrappedValue: wb)
        _journey = StateObject(wrappedValue: j)
        _session = StateObject(wrappedValue: FeedSession(wordBook: wb, journey: j))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if !session.onShorts { browserBar }
                FeedBrowserView(bridge: bridge, session: session)
                    .ignoresSafeArea(edges: session.onShorts ? .all : .bottom)
                    // While a card asks something, VoiceOver must not read YouTube's English title underneath.
                    .accessibilityHidden(session.moment != nil || session.grammar != nil)
            }

            if session.onShorts {
                if session.currentVideoId == nil || session.bridgeStale {
                    loadingHint
                }
                if session.moment == nil && session.grammar == nil {
                    SubtitleOverlay(session: session)
                        .padding(.bottom, 170)   // sit above the Shorts title/channel row
                }
                dashboardButton
                if let l = session.activeLesson, session.currentVideoId == l.youtubeId, session.original == nil {
                    lessonBadge(l)
                } else if showFeedChip { feedChip }
            }

            if let m = session.moment {
                LearningCard(moment: m, session: session)
                    .id(m.id)
                    .onAppear { SoundFX.play(.pop) }
                    .transition(.opacity)
            }

            // Small toast when a usable reward is earned or a freeze is used.
            if let earned = rewards.lastEarned {
                VStack {
                    HStack(spacing: 8) {
                        MascotImage(mood: earned.icon == .freeze ? .freeze : .gift, size: 30, animated: false)
                        Image(systemName: earned.icon.symbol).font(.footnote.weight(.bold)).foregroundStyle(.white)
                            .accessibilityLabel(earned.icon.name)
                        Text(earned.text).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .glass(in: Capsule(), tint: .black.opacity(0.35))
                        .environment(\.colorScheme, .dark)
                        .padding(.top, 110)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: earned) {
                    SoundFX.play(.reward)
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { rewards.lastEarned = nil }
                }
                .allowsHitTesting(false)
                .accessibilityIdentifier("reward-toast")
            }

            if let o = session.original, session.onShorts {
                OriginalCardView(card: o, session: session)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let g = session.grammar, session.onShorts {
                GrammarCardView(moment: g, session: session)
                    .id(g.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Milestones while scrolling: words today, % to the next unlock, kana (top of the feed, never blocks).
            if let n = session.nudge, session.onShorts, session.unlock == nil {
                VStack {
                    NudgeBanner(nudge: n) { session.nudge = nil }
                        .id(n.id)
                        // Just below the Dynamic Island, in the black YouTube bar above the video.
                        .padding(.top, 50)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }

            // Just unlocked a practice type / finished kana: a short burst over the feed (the Short keeps playing).
            if let u = session.unlock, session.onShorts {
                UnlockCelebration(event: u) { withAnimation { session.unlock = nil } }
                    .id(u.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.moment)
        .animation(.easeOut(duration: 0.25), value: session.original?.phrase.id)
        .animation(.easeOut(duration: 0.25), value: session.grammar?.id)
        .animation(.easeOut(duration: 0.25), value: session.unlock?.id)
        .animation(.easeOut(duration: 0.2), value: session.onShorts)
        .animation(.spring(duration: 0.35), value: rewards.lastEarned)
        .background(Color.black)
        .statusBarHidden()
        .onAppear {
            Speech.shared.prewarm()
            SoundFX.prewarm()
            // Cloud save (Supabase): merge on launch if signed in, then keep uploading changes.
            CloudSync.shared.attach(wordBook: wordBook, journey: journey, session: session)
            // Missed a day? A saved streak freeze covers it automatically.
            Rewards.shared.applyFreezes(activeDays: wordBook.activeDays, key: WordBook.key)
            Rewards.shared.checkStreak(wordBook.streak)
            // Personal path (Jev) and the lesson video catalog.
            PathStore.shared.update(session: session, journey: journey, wordBook: wordBook)
            Task { await LessonLibrary.shared.refresh() }
            // Debug/demo: `-dashboard` opens the あ dashboard at launch (used for screenshots).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-dashboard") { showDashboard = true }
            if args.contains("-recap") { showRecap = true }
            // First launch: the visual onboarding (skipped for scripted/test launches; `-onboarding` forces it).
            // People who already saw the old text guide count as onboarded.
            if seenGuide { onboarded = true }
            if args.contains("-onboarding") || (!onboarded && !args.dropFirst().contains(where: { $0.hasPrefix("-") })) {
                showGuide = true
                session.web.pause()
            }
            #if DEBUG
            if args.contains("-lab") { showLab = true }
            #endif
        }
        .onChange(of: showDashboard) { _, open in
            session.dashboardOpen = open || showRecap
            if open { PathStore.shared.update(session: session, journey: journey, wordBook: wordBook) }
        }
        .onChange(of: showRecap) { _, open in session.dashboardOpen = open || showDashboard }
        .onChange(of: showLab) { _, open in session.dashboardOpen = open || showDashboard || showRecap }
        .onChange(of: session.labRoute) { _, route in
            guard let route else { return }
            showDashboard = false; showLab = false
            if route == "recap" { showRecap = true }
            session.labRoute = nil
        }
        .onChange(of: session.recapRequested) { _, req in if req { showDashboard = false; showRecap = true } }
        .sheet(isPresented: $showFeedSheet) { JapaneseFeedSheet(session: session, journey: journey) }
        .onChange(of: showFeedSheet) { _, open in session.dashboardOpen = open || showDashboard || showRecap }
        .fullScreenCover(isPresented: $showGuide, onDismiss: { onboarded = true; seenGuide = true; session.web.play() }) {
            OnboardingView(session: session) { showGuide = false }
        }
        .onChange(of: showGuide) { _, open in session.dashboardOpen = open || showDashboard || showRecap }
        .sheet(isPresented: $showDashboard) {
            DashboardView(session: session, wordBook: wordBook, journey: journey) { showDashboard = false }
                .presentationDetents([.large])
        }
        #if DEBUG
        .sheet(isPresented: $showLab) {
            NavigationStack { QuestionLab(session: session, wordBook: wordBook, journey: journey) }
        }
        #endif
        .fullScreenCover(isPresented: $showRecap) {
            SessionRecapView(journey: journey, wordBook: wordBook, reachedLimit: session.recapRequested,
                             dailyLimitMinutes: session.settings.dailyLimitMinutes,
                             vocab: session.vocab, level: session.settings.jlptLevel,
                             onGoodStop: {
                                 journey.goodStop()
                                 session.startNewSession()
                                 showRecap = false
                                 showDashboard = true
                             },
                             onKeepScrolling: {
                                 session.recapRequested = false
                                 showRecap = false
                                 session.web.play()
                             })
        }
    }

    /// After ~5 mostly-English Shorts: point to the feed fix where the problem is felt (it lived only in Progress).
    private var showFeedChip: Bool {
        session.moment == nil && session.original == nil && !session.settings.japaneseFeed
            && session.swipesThisSession >= 5 && journey.japaneseFeedShare < 0.3
            && feedChipDismissedDay != JourneyStore.dayKey(Date())
    }

    private var feedChip: some View {
        VStack {
            HStack(spacing: 8) {
                Button { showFeedSheet = true } label: {
                    Label("\(Int(journey.japaneseFeedShare * 100))% 🇯🇵 +", systemImage: "globe.asia.australia.fill")
                        .accessibilityLabel("\(Int(journey.japaneseFeedShare * 100))% Japanese. Get more Japanese Shorts")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feed-chip")
                Button { feedChipDismissedDay = JourneyStore.dayKey(Date()) } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
                .buttonStyle(.plain).accessibilityLabel("Not today")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass(in: Capsule(), interactive: true)
            .environment(\.colorScheme, .dark)
            .padding(.top, 60).padding(.leading, 12).padding(.trailing, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
    }

    /// On an Upscroll lesson Short: what it is, and its checkpoints (filled = done).
    private func lessonBadge(_ l: LessonVideo) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill").foregroundStyle(Brand.OnDark.gold)
                Text(l.title).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(0..<l.checkpoints.count, id: \.self) { i in
                        Circle().fill(session.lessonCheckpointsDone.contains(i) ? Brand.OnDark.gold : .white.opacity(0.35)).frame(width: 7, height: 7)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glass(in: Capsule())
            .environment(\.colorScheme, .dark)
            .padding(.top, 60).padding(.leading, 12).padding(.trailing, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Upscroll lesson: \(l.title). \(session.lessonCheckpointsDone.count) of \(l.checkpoints.count) checkpoints done")
        .accessibilityIdentifier("lesson-badge")
    }

    /// Shown while no Short is confirmed on screen (first load, swipe in progress, stalled page).
    private var loadingHint: some View {
        VStack(spacing: 10) {
            ProgressView().tint(.white)
            Text(session.bridgeStale ? "The video isn't responding" : "Loading Shorts…")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            if session.bridgeStale {
                Button("Reload") { session.web.webView?.reload() }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Brand.OnDark.gold, in: Capsule()).foregroundStyle(.black)
                    .accessibilityIdentifier("reload-feed")
            }
        }
        .padding(16)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(session.bridgeStale)
        .accessibilityIdentifier("feed-loading")
    }

    /// Native bar shown on YouTube home, Google sign-in and other non-Shorts pages:
    /// always a way back to the feed, plus sign-in status.
    private var browserBar: some View {
        HStack(spacing: 10) {
            Button { session.web.open(WebController.feedURL(japanese: session.settings.japaneseFeed)) } label: {
                Label("Shorts", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .glass(in: Capsule(), interactive: true)
            }
            Spacer()
            Text(pageTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if session.onYouTube {
                if session.signedIn == true {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Brand.success)
                        .font(.title3)
                } else {
                    Button { session.web.open(WebController.signInURL) } label: {
                        Text("Sign in")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Brand.OnDark.gold, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
            }
            Button { openDashboard() } label: {
                Text("あ").font(.headline)
                    .frame(width: 36, height: 36)
                    .glass(in: Circle(), interactive: true)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black)
    }


    /// あ always opens your words & progress. The session recap only appears at the daily scroll limit,
    /// so the badge never does something different depending on hidden timers.
    private func openDashboard() {
        guard !showLab else { return }   // long-press opened the Question Lab
        showDashboard = true
    }

    private var pageTitle: String {
        guard let host = session.pageURL?.host else { return "" }
        if host.hasSuffix("youtube.com") { return "YouTube" }
        if host.hasSuffix("google.com") { return "Google sign-in" }
        return host
    }

    /// あ button: today's progress at a glance, opens the dashboard.
    private var dashboardButton: some View {
        VStack {
            HStack {
                Spacer()
                let n = wordBook.metToday.count
                Button { openDashboard() } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Text("あ")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .glass(in: Circle(), interactive: true)
                                .environment(\.colorScheme, .dark)
                            if n > 0 {
                                Text("\(n)")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Brand.OnDark.gold, in: Capsule())
                                    .offset(x: 6, y: -4)
                            }
                        }
                    }
                }
                .accessibilityLabel(n > 0 ? "My words: \(n) Japanese words met today (seen in Shorts, not yet necessarily learned)" : "My words")
                .accessibilityHint("Opens your words, meanings and progress")
                .accessibilityIdentifier("dashboard-button")
                #if DEBUG
                // Debug builds: long-press あ opens the Question Lab.
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in showLab = true })
                #endif
                .padding(.trailing, 12)
            }
            Spacer()
        }
        .padding(.top, 54)
    }
}
