import SwiftUI

/// Native subtitle bar over the feed: the English line with this video's learning words swapped to Japanese.
/// It never takes touches except on the Japanese word itself, so swiping the feed still works everywhere else.
struct SubtitleOverlay: View {
    @ObservedObject var session: FeedSession
    /// Word whose meaning bubble is showing (tap the yellow word to look it up).
    @State private var lookedUp: VocabEntry?
    @State private var hideTask: Task<Void, Never>?
    /// The last yellow word, kept as a small tappable chip for ~4 s after its caption line moves on
    /// (lines change every second or two, too fast to notice the swap).
    @State private var recent: VocabEntry?
    @State private var recentTask: Task<Void, Never>?
    /// The Short the last yellow word belonged to: the chip never carries over to the next clip.
    @State private var swapVideo: String?

    var body: some View {
        VStack(spacing: 6) {
            if let e = lookedUp {
                meaningBubble(e)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if let e = recent, session.currentSwap == nil {
                Button { lookUp(e); Speech.shared.say(e.kana) } label: {
                    HStack(spacing: 6) {
                        Text(e.kana).font(.subheadline.weight(.heavy)).foregroundStyle(Brand.OnDark.gold)
                        Text(e.romaji).font(.caption.weight(.semibold)).foregroundStyle(.white)
                        Image(systemName: "hand.tap.fill").font(.subheadline).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glass(in: Capsule(), tint: .black.opacity(0.4))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Just now: \(e.kana), \(e.romaji). Tap for meaning")
                .accessibilityIdentifier("recent-word-chip")
            }
            if let r = session.currentRecord, r.isAd == true {
                Image(systemName: "megaphone.fill").font(.subheadline).foregroundStyle(.white)
                    .accessibilityLabel("Ad, no words")
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.35), in: Capsule())
                    .allowsHitTesting(false).accessibilityIdentifier("ad-hint")
            } else if let r = session.currentRecord, r.isDubbed == true, session.currentSourceCue != nil {
                Image(systemName: "waveform.badge.exclamationmark").font(.subheadline).foregroundStyle(.white)
                    .accessibilityLabel("Auto-dubbed. Captions are the original language")
                    .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.35), in: Capsule())
                    .allowsHitTesting(false).accessibilityIdentifier("dub-hint")
            }
            if let r = session.currentRecord, r.sourceCues.isEmpty, r.sourceEmpty != nil || r.info != nil, session.currentTime > 4 {
                // So a beginner knows the app is working on clips without speech captions.
                Label("No captions", systemImage: "rectangle.on.rectangle").labelStyle(.iconOnly)
                    .font(.subheadline).foregroundStyle(.white)
                    .accessibilityLabel("No captions. Japanese comes as a card")
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.black.opacity(0.35), in: Capsule())
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("no-captions-hint")
            }
            if let cue = session.currentSourceCue {
                line(for: cue)
                    .id(cue.start)
                    .transition(.opacity)
            }
            if session.settings.showJapaneseLineWhilePlaying, let ja = session.currentJapaneseCue {
                Text(ja.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 20)
        .animation(.easeOut(duration: 0.15), value: session.currentSourceCue)
        .animation(.spring(duration: 0.25), value: lookedUp)
        .onChange(of: session.currentVideoId) { _, _ in lookedUp = nil; recent = nil }
        .onChange(of: session.currentSwap?.entry.id) { old, new in
            // A soft haptic tap when a yellow word appears, so it's noticed while watching.
            if new != nil { swapVideo = session.currentVideoId }
            if new != nil, old == nil { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5) }
            guard new == nil, let old, let e = session.vocab.byId[old],
                  swapVideo != nil, swapVideo == session.currentVideoId else { return }   // swiped away: no chip
            recent = e
            recentTask?.cancel()
            recentTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { withAnimation { recent = nil } }
            }
        }
        .animation(.easeOut(duration: 0.2), value: recent)
    }

    /// Instant lookup: kana, romaji and the English meaning right above the line.
    private func meaningBubble(_ e: VocabEntry) -> some View {
        HStack(spacing: 8) {
            Text(e.mainKana).font(.headline.weight(.heavy)).foregroundStyle(Brand.OnDark.gold)
            Text(e.mainRomaji).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text("=").foregroundStyle(.white)
            Text(session.vocab.shortMeaning(e)).font(.headline).foregroundStyle(.white)
            Image(systemName: "speaker.wave.2.fill").font(.subheadline).foregroundStyle(Brand.OnDark.gold)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .glass(cornerRadius: 14, tint: .black.opacity(0.55))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("word-meaning")
        .onTapGesture { Speech.shared.say(e.kana) }
    }

    private func lookUp(_ e: VocabEntry) {
        lookedUp = e
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { lookedUp = nil }
        }
    }

    @ViewBuilder
    private func line(for cue: Cue) -> some View {
        if let swap = session.currentSwap {
            let before = String(cue.text[cue.text.startIndex..<swap.range.lowerBound])
            let after = String(cue.text[swap.range.upperBound...])
            let shown = session.settings.scriptLevel.display(swap.entry)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                plain(before)
                Button {
                    Speech.shared.say(swap.entry.mainKana)
                    session.wordBook.recordHeard(swap.entry.id)
                    lookUp(swap.entry)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 0) {
                        if let sub = shown.sub {
                            Text(sub).font(.subheadline).foregroundStyle(Brand.OnDark.gold)
                        }
                        Text(shown.main).font(.headline.weight(.heavy)).foregroundStyle(Brand.OnDark.gold)
                    }
                    .padding(.horizontal, 4)
                    // Soft pulse when a Japanese word appears, so it's noticed in a fast-changing line.
                    .modifier(PulseOnAppear())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(swap.entry.kana), \(swap.entry.romaji). Tap for meaning")
                .accessibilityIdentifier("swap-word")
                plain(after)
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .glass(cornerRadius: 14, tint: .black.opacity(0.3))
        } else if Romanize.isJapanese(cue.text), session.settings.scriptLevel.rawValue <= ScriptLevel.kanaRomaji.rawValue {
            // A full Japanese line (Japanese-audio Short): add romaji so the reading level applies here too.
            VStack(spacing: 2) {
                plain(cue.text).multilineTextAlignment(.center)
                Text(Romanize.pronounced(cue.text))
                    .font(.subheadline).foregroundStyle(Brand.OnDark.gold)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .glass(cornerRadius: 14, tint: .black.opacity(0.3))
            .allowsHitTesting(false)
            .accessibilityIdentifier("japanese-line-romaji")
        } else {
            plain(cue.text)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .glass(cornerRadius: 14, tint: .black.opacity(0.3))
                .allowsHitTesting(false)
        }
    }

    private func plain(_ s: String) -> some View {
        Text(s).font(.headline).foregroundStyle(.white).allowsHitTesting(false)
    }
}

/// One gentle grow-and-settle when the view appears.
struct PulseOnAppear: ViewModifier {
    @State private var big = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(big ? 1.25 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.25)) { big = true }
                withAnimation(.easeInOut(duration: 0.4).delay(0.3)) { big = false }
            }
    }
}
