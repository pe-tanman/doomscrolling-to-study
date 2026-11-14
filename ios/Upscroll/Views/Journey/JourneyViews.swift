import SwiftUI

// MARK: - Journey map (Home hero and the full map)

/// The illustrated town with the learner's own route drawn through it: places in their personal order,
/// done ones ticked, the current one highlighted with the mascot.
struct JourneyMap: View {
    @ObservedObject var journey: JourneyStore
    var compact = false
    var onPick: (Place) -> Void = { _ in }

    /// Two drawings of the same town (one per shape), each with every curriculum place drawn as a landmark.
    /// Landmark centres are fractions of the image; pins sit on them.
    struct Art { let image: String; let aspect: CGFloat; let landmarks: [String: CGPoint] }
    static let wide = Art(image: "journey_map_wide", aspect: 1024.0 / 768.0, landmarks: [
        "arrival": CGPoint(x: 0.17, y: 0.83), "cafe": CGPoint(x: 0.48, y: 0.78), "station": CGPoint(x: 0.82, y: 0.73),
        "konbini": CGPoint(x: 0.20, y: 0.48), "shrine": CGPoint(x: 0.53, y: 0.42), "ramen": CGPoint(x: 0.15, y: 0.22),
        "castle": CGPoint(x: 0.85, y: 0.17)])
    static let tall = Art(image: "journey_map_tall", aspect: 608.0 / 1088.0, landmarks: [
        "arrival": CGPoint(x: 0.25, y: 0.90), "cafe": CGPoint(x: 0.31, y: 0.745), "station": CGPoint(x: 0.69, y: 0.645),
        "konbini": CGPoint(x: 0.23, y: 0.515), "shrine": CGPoint(x: 0.67, y: 0.415), "ramen": CGPoint(x: 0.21, y: 0.30),
        "castle": CGPoint(x: 0.79, y: 0.185)])

    var body: some View {
        GeometryReader { g in
            let art = g.size.width / max(1, g.size.height) > 0.9 ? Self.wide : Self.tall
            let places = journey.orderedPlaces
            let pts = places.map { point($0, art: art, in: g.size) }
            ZStack {
                Image(art.image).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                    .accessibilityHidden(true)
                // The learner's route between landmarks: solid up to where you are, dashed after.
                let cur = places.firstIndex { $0.id == journey.currentPlace.id } ?? 0
                route(Array(pts.prefix(cur + 1))).stroke(Brand.violet, style: StrokeStyle(lineWidth: compact ? 5 : 6, lineCap: .round, lineJoin: .round))
                route(Array(pts.suffix(from: cur))).stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: compact ? 4 : 5, lineCap: .round, lineJoin: .round, dash: [2, 9]))
                ForEach(Array(places.enumerated()), id: \.element.id) { i, p in
                    pin(p, step: i + 1)
                        .position(pts[i])
                        .onTapGesture { onPick(p) }
                        // On Home the whole map is one button (opens the full map); pins mustn't swallow the tap.
                        .allowsHitTesting(!compact)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Landmark position in the view, through the same scale-to-fill crop as the image.
    private func point(_ p: Place, art: Art, in size: CGSize) -> CGPoint {
        let f = art.landmarks[p.id] ?? CGPoint(x: p.pin.x, y: p.pin.y)
        let scale = max(size.width / art.aspect, size.height)   // displayed image height
        let w = scale * art.aspect, h = scale
        let x = (size.width - w) / 2 + f.x * w, y = (size.height - h) / 2 + f.y * h
        // Keep pins on screen even where the crop is tight.
        return CGPoint(x: min(max(x, 26), size.width - 26), y: min(max(y, 26), size.height - 30))
    }

    private func route(_ pts: [CGPoint]) -> Path {
        Path { path in
            guard let first = pts.first else { return }
            path.move(to: first)
            for (a, b) in zip(pts, pts.dropFirst()) {
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 18)
                path.addQuadCurve(to: b, control: mid)
            }
        }
    }

    private func pin(_ p: Place, step: Int) -> some View {
        let st = journey.state(p)
        let size: CGFloat = compact ? (st == .current ? 50 : 34) : (st == .current ? 64 : 46)
        return ZStack {
            Circle().fill(st == .done ? Brand.success : st == .current ? Brand.violet : .white)
            if st == .current {
                MascotImage(mood: .map, size: size * 1.05, animated: !compact)
            } else if st == .done {
                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(.white)
            } else {
                Text("\(step)").font(.system(size: size * 0.42, weight: .heavy, design: .rounded)).foregroundStyle(Brand.violetDeep)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .overlay(alignment: .bottom) {
            if !compact || st == .current {
                Text(p.name).font(.caption2.weight(.bold)).foregroundStyle(st == .current ? .white : Brand.ink)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(st == .current ? Brand.violetDeep : .white, in: Capsule())
                    .fixedSize()
                    .offset(y: 16)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step): \(p.name), \(st == .done ? "done" : st == .current ? "you are here" : "coming up")")
        .accessibilityAddTraits(.isButton)
    }
}

/// Home's centrepiece: the whole journey at a glance, then where you are now.
struct JourneyHero: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    @ObservedObject private var paths = PathStore.shared
    @State private var open: Place?

    private var goal: LearningGoal { LearningGoal(rawValue: session.settings.goal) ?? .culture }

    var body: some View {
        let place = journey.currentPlace
        VStack(spacing: 0) {
            NavigationLink { WorldView(session: session, wordBook: wordBook, journey: journey) } label: {
                JourneyMap(journey: journey, compact: true)
                    .frame(height: 250)
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 6) {
                            chip("\(goal.emoji) \(goal.title)", Brand.ink, .white.opacity(0.94))
                            if paths.path?.source == "jev" {
                                Image(systemName: "sparkles").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 30, height: 30).background(Brand.violet, in: Circle())
                                    .accessibilityLabel("Personalised by Jev")
                                    .accessibilityIdentifier("path-jev")
                            }
                        }
                        .padding(10)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.subheadline.weight(.bold)).foregroundStyle(Brand.ink)
                            .frame(width: 32, height: 32).background(.white.opacity(0.94), in: Circle()).padding(10)
                            .accessibilityLabel("Open the full map")
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("journey-map")

            // Where you are now.
            Button { open = place } label: {
                HStack(spacing: 12) {
                    Image(place.scene).resizable().scaledToFill().frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(place.name).font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                            Text(place.japanese).font(Brand.jp(14)).foregroundStyle(Brand.ink2)
                            Spacer(minLength: 0)
                            Label("\(journey.phrasesDone(place))/\(place.phrases.count)", systemImage: "text.bubble.fill")
                                .font(.subheadline.weight(.bold)).foregroundStyle(Brand.violetDeep)
                                .accessibilityLabel("\(journey.phrasesDone(place)) of \(place.phrases.count) phrases")
                        }
                        HStack(spacing: 4) {
                            ForEach(Skill.allCases) { s in
                                let have = place.phrases.filter { journey.skills($0.id).contains(s) }.count
                                ProgressBar(value: Double(have) / Double(place.phrases.count), color: s.color, height: 7)
                                    .overlay(alignment: .top) {
                                        if paths.focus == s {
                                            Image(systemName: "scope").font(.caption2.weight(.heavy)).foregroundStyle(s.color).offset(y: -13)
                                        }
                                    }
                            }
                        }
                        .accessibilityElement()
                        .accessibilityLabel(paths.focus.map { "Focus: \($0.title)" } ?? "Skill progress")
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("current-place")
        }
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sheet(item: $open) { p in
            NavigationStack { PlaceView(place: p, session: session, wordBook: wordBook, journey: journey) }
        }
    }

    private func chip(_ t: String, _ fg: Color, _ bg: Color) -> some View {
        Text(t).font(.subheadline.weight(.bold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 6).background(bg, in: Capsule())
    }
}

/// The learner's route as a row of steps: scene, ring of progress, tick when done.
struct PathStrip: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    @State private var open: Place?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(journey.orderedPlaces.enumerated()), id: \.element.id) { i, p in
                        if i > 0 {
                            Capsule().fill(journey.state(journey.orderedPlaces[i - 1]) == .done ? Brand.violet : Brand.line)
                                .frame(width: 16, height: 4).padding(.bottom, 24)
                        }
                        step(p, i + 1).id(p.id)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear { proxy.scrollTo(journey.currentPlace.id, anchor: .center) }
        }
        .sheet(item: $open) { p in
            NavigationStack { PlaceView(place: p, session: session, wordBook: wordBook, journey: journey) }
        }
        .accessibilityIdentifier("path-strip")
    }

    private func step(_ p: Place, _ n: Int) -> some View {
        let st = journey.state(p)
        let frac = Double(journey.phrasesDone(p)) / Double(max(1, p.phrases.count))
        return Button { open = p } label: {
            VStack(spacing: 6) {
                ZStack {
                    Image(p.scene).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(Circle())
                        .saturation(st == .locked ? 0.3 : 1).opacity(st == .locked ? 0.7 : 1)
                    Circle().stroke(Brand.line, lineWidth: 4).frame(width: 60, height: 60)
                    Circle().trim(from: 0, to: st == .done ? 1 : frac)
                        .stroke(st == .done ? Brand.success : Brand.violet, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 60, height: 60)
                    if st == .done {
                        Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, Brand.success)
                            .offset(x: 22, y: -22)
                    }
                }
                Text(p.name).font(.caption.weight(.bold)).foregroundStyle(st == .current ? Brand.violetDeep : Brand.ink).lineLimit(1)
            }
            .frame(width: 70)
            .padding(.vertical, 6)
            .background(st == .current ? Brand.violetSoft : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(n): \(p.name), \(st == .done ? "done" : st == .current ? "you are here" : "coming up")")
    }
}

// MARK: - Lesson shelf

/// Upscroll lesson Shorts in path order. Tap → plays in the feed.
struct LessonShelf: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var journey: JourneyStore
    @ObservedObject private var library = LessonLibrary.shared
    var onPlay: () -> Void

    var body: some View {
        let lessons = library.ordered(placeOrder: journey.orderedPlaces.map(\.id))
        if !lessons.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Lessons", systemImage: "graduationcap.fill").font(.title3.weight(.bold)).fontDesign(.rounded).foregroundStyle(Brand.ink)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(lessons) { l in
                            Button { onPlay(); session.playLesson(l) } label: { tile(l) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("lesson-\(l.id)")
                        }
                    }
                }
            }
        }
    }

    private func tile(_ l: LessonVideo) -> some View {
        let watched = library.watched.contains(l.id)
        return ZStack(alignment: .bottomLeading) {
            AsyncImage(url: l.thumbnail) { img in img.resizable().scaledToFill() } placeholder: { Brand.violetSoft }
                .frame(width: 112, height: 176).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: watched ? "checkmark.circle.fill" : "play.circle.fill").font(.title2)
                    .foregroundStyle(.white, watched ? Brand.success : Brand.violet)
                Text(l.title).font(.caption.weight(.bold)).foregroundStyle(.white).lineLimit(2)
            }
            .padding(8)
        }
        .frame(width: 112, height: 176)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lesson: \(l.title)\(watched ? ", watched" : "")")
    }
}

// MARK: - My phrases (from your own Shorts)

struct MyPhrasesCard: View {
    @ObservedObject private var book = PhraseBook.shared

    var body: some View {
        if !book.phrases.isEmpty {
            NavigationLink { PhraseListView() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(book.phrases.count)", systemImage: "text.bubble.fill")
                            .font(.title2.weight(.heavy)).fontDesign(.rounded).foregroundStyle(Brand.violetDeep)
                        Text("phrases from your Shorts").font(.headline).foregroundStyle(Brand.ink)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Brand.ink3)
                    }
                    ForEach(book.phrases.prefix(2)) { p in
                        HStack(spacing: 10) {
                            Text(p.ja).font(Brand.jp(17, bold: true)).foregroundStyle(Brand.ink).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(p.en).font(.subheadline).foregroundStyle(Brand.ink2).lineLimit(1)
                            CoverageDots(skills: p.skills, size: 8)
                        }
                    }
                }
                .brandCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("my-phrases")
        }
    }
}

struct PhraseListView: View {
    @ObservedObject private var book = PhraseBook.shared

    var body: some View {
        List(book.phrases) { p in
            Button { Speech.shared.say(p.ja) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Romanize.pronounced(p.ja)).font(.caption.weight(.semibold)).foregroundStyle(Brand.violetDeep)
                        Text(p.ja).font(Brand.jp(19, bold: true)).foregroundStyle(Brand.ink)
                        Text(p.en).font(.subheadline).foregroundStyle(Brand.ink)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(Brand.violet)
                        CoverageDots(skills: p.skills, size: 9)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(p.ja), \(p.en)")
        }
        .scrollContentBackground(.hidden)
        .background(Brand.sky)
        .navigationTitle("My phrases")
        .navigationBarTitleDisplayMode(.inline)
    }
}
