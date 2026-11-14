import SwiftUI

/// Cards between or on top of Shorts:
/// - mini-reel / quest: an Upscroll original built for the phrase you're missing most (full-screen art);
/// - from this Short: a whole line of the Short you're watching, learned then built (the video stays visible);
/// - lesson: a checkpoint of an Upscroll lesson Short (the video stays visible).
struct OriginalCardView: View {
    let card: OriginalCard
    @ObservedObject var session: FeedSession
    /// From-this-Short cards: first see and hear the line, then build it.
    @State private var building = false

    private var overVideo: Bool { card.kind == .fromShort || card.kind == .lesson }

    var body: some View {
        ZStack(alignment: .bottom) {
            if overVideo {
                // The paused Short stays on screen behind a soft scrim: the phrase is *from this video*.
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
            } else {
                // Fill the screen without letting a wide image widen the layout (it pushed the card off-screen).
                Color.clear
                    .overlay(Image(card.kind == .miniReel ? "scene_reel" : card.place.scene).resizable().scaledToFill())
                    .clipped()
                    .ignoresSafeArea()
                    .overlay(LinearGradient(colors: [.clear, Color(hex: 0x1A1433, opacity: 0.7)], startPoint: .center, endPoint: .bottom).ignoresSafeArea())
                    .accessibilityHidden(true)
            }

            VStack {
                HStack {
                    badge
                    Spacer()
                    Button { skip() } label: {
                        Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(.black.opacity(0.35), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip")
                    .accessibilityIdentifier("original-skip")
                }
                .padding(.horizontal, 16).padding(.top, 58)
                Spacer()
            }

            VStack(alignment: .trailing, spacing: -18) {
                if !overVideo { MascotImage(mood: .cheer, size: 84).padding(.trailing, 8) }
                if let w = card.fromFeedWord {
                    Label("\(w.kana) = \(w.meaning)", systemImage: "arrow.turn.down.right")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .accessibilityLabel("You just saw \(w.kana), \(w.meaning), in a Short. Here it is in a phrase")
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Brand.violet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("original-bridge")
                }
                Group {
                    if let sp = card.source, !building {
                        PhraseIntro(phrase: sp) { withAnimation(.snappy) { building = true } }
                    } else {
                        PhrasePractice(phrase: card.phrase, skill: card.skill, place: card.place) { ok in
                            session.finishOriginal(correct: ok)
                        }
                    }
                }
                .brandCard(Brand.surface.opacity(0.97))
                .environment(\.colorScheme, .light)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(card.kind == .fromShort ? "short-phrase-card" : card.kind == .lesson ? "lesson-card" : "original-card")
        .onAppear { SoundFX.play(.pop) }
    }

    private var badge: some View {
        let (title, symbol): (String, String) = switch card.kind {
        case .miniReel: ("Mini-reel", "film.fill")
        case .quest: ("Quest", "flag.fill")
        case .fromShort: ("From this Short", "text.bubble.fill")
        case .lesson: ("Lesson", "graduationcap.fill")
        }
        return Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(card.kind == .lesson ? Brand.sunDeep : Brand.violet, in: Capsule())
    }

    private func skip() {
        // A skipped phrase from this Short isn't saved; skipping a practice card just moves on.
        if card.kind == .fromShort, !building { session.dismissOriginal() } else { session.finishOriginal(correct: false) }
    }
}

/// Step 1 of a phrase from this Short: the line in Japanese, how it sounds, what it means. Big and simple.
struct PhraseIntro: View {
    let phrase: ShortPhrase
    var onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Romanize.pronounced(phrase.ja)).font(.headline).foregroundStyle(Brand.violetDeep)
                    Text(phrase.ja).font(Brand.jp(28, bold: true, relativeTo: .title)).foregroundStyle(Brand.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(spacing: 8) {
                    Button { Speech.shared.say(phrase.ja) } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.title3).foregroundStyle(.white)
                            .frame(width: 52, height: 52).background(Brand.violet, in: Circle())
                    }
                    .accessibilityLabel("Play")
                    Button { Speech.shared.saySlowly(phrase.ja) } label: {
                        Image(systemName: "tortoise.fill").font(.subheadline).foregroundStyle(Brand.violetDeep)
                            .frame(width: 40, height: 40).background(Brand.violetSoft, in: Circle())
                    }
                    .accessibilityLabel("Play slowly")
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                Image(systemName: "equal.circle.fill").foregroundStyle(Brand.success)
                Text(phrase.en).font(.title3.weight(.semibold)).foregroundStyle(Brand.ink)
            }
            // The tiles you'll build it from, as a preview.
            HStack(spacing: 6) {
                ForEach(Array(phrase.tiles.enumerated()), id: \.offset) { _, t in
                    Text(t).font(Brand.jp(15, bold: true)).foregroundStyle(Brand.violetDeep)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Brand.violetSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .accessibilityHidden(true)
            Button(action: onBuild) { Label("Build it", systemImage: "square.stack.3d.up.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.brandPrimary)
                .accessibilityIdentifier("phrase-build")
        }
    }
}
