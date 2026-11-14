import SwiftUI

enum DashboardTab: Hashable { case home, learn, progress }

/// The あ dashboard: Home (with the journey map) · Learn · Progress.
struct DashboardView: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @ObservedObject var journey: JourneyStore
    var onClose: () -> Void
    @State private var tab: DashboardTab = .home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(session: session, wordBook: wordBook, journey: journey, onKeepScrolling: onClose, onShowProgress: { tab = .progress }) }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(DashboardTab.home)
            NavigationStack { LearnView(session: session, wordBook: wordBook, journey: journey) }
                .tabItem { Label("Learn", systemImage: "sparkles") }
                .tag(DashboardTab.learn)
            NavigationStack { JourneyProgressView(session: session, wordBook: wordBook, journey: journey) }
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
                .tag(DashboardTab.progress)
        }
        .tint(Brand.violet)
        .environment(\.colorScheme, .light)
    }
}

// MARK: Shared pieces

struct WordChip: View {
    let entry: VocabEntry
    let level: ScriptLevel
    var progress: WordProgress?

    var body: some View {
        let shown = level.display(entry)
        Button {
            Speech.shared.say(entry.kana)
        } label: {
            VStack(spacing: 4) {
                Text(entry.emoji).font(.title)
                Text(shown.main).font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(entry.meaning).font(.subheadline).lineLimit(1)
                if let p = progress { BoxDots(box: p.box) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 6)
            .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.kana), \(entry.meaning)")
        .accessibilityHint("Plays the word")
    }
}

/// Leitner box as five dots (filled = progress).
struct BoxDots: View {
    let box: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < box ? (box >= 5 ? Brand.success : Brand.violet) : Brand.line)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(value).font(.title2.weight(.bold)).contentTransition(.numericText())
            Text(label).font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// English line with one word highlighted (used for "where you met it").
func highlighted(_ line: String, entry: VocabEntry, vocab: VocabStore) -> AttributedString {
    var s = AttributedString(line)
    if let m = vocab.candidates(in: line, allSenses: true).first(where: { $0.entry.id == entry.id }),
       let lo = AttributedString.Index(m.range.lowerBound, within: s),
       let hi = AttributedString.Index(m.range.upperBound, within: s) {
        s[lo..<hi].foregroundColor = Brand.violetDeep
        s[lo..<hi].font = .body.weight(.bold)
    }
    return s
}
