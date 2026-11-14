import SwiftUI

struct WordsTab: View {
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook
    @State private var status: WordStatus = .all
    @State private var query = ""

    private var rows: [(WordProgress, VocabEntry)] {
        wordBook.list(status).compactMap { p in session.vocab.byId[p.id].map { (p, $0) } }.filter { _, e in
            query.isEmpty || [e.kana, e.romaji, e.meaning, e.kanji ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $status) {
                    ForEach(WordStatus.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if rows.isEmpty {
                ContentUnavailableView(wordBook.words.isEmpty ? "No words yet" : "Nothing here",
                                       systemImage: "character.book.closed.ja")
            }
            ForEach(rows, id: \.0.id) { p, e in
                NavigationLink {
                    WordDetail(entry: e, session: session, wordBook: wordBook)
                } label: {
                    row(p, e)
                }
                .swipeActions(edge: .trailing) {
                    Button(p.isKnown ? "Relearn" : "Known") { wordBook.markKnown(e.id, !p.isKnown) }
                        .tint(p.isKnown ? Brand.warn : Brand.success)
                }
                .swipeActions(edge: .leading) {
                    Button { Speech.shared.say(e.kana) } label: { Label("Hear", systemImage: "speaker.wave.2.fill") }
                        .tint(Brand.violetDeep)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Brand.sky)
        .searchable(text: $query, prompt: "Search kana, romaji, meaning")
        .navigationTitle("My words · \(wordBook.words.count)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ p: WordProgress, _ e: VocabEntry) -> some View {
        HStack(spacing: 12) {
            Text(e.emoji).font(.title2).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(e.written).font(.headline)
                    if e.kanji != nil { Text(e.kana).font(.subheadline).foregroundStyle(Brand.violetDeep) }
                    Text(e.levelName)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Brand.violetSoft, in: Capsule())
                        .foregroundStyle(Brand.violetDeep)
                }
                Text("\(e.romaji) · \(e.meaning)").font(.subheadline)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                BoxDots(box: p.box)
                if p.isDue { Image(systemName: "clock.fill").font(.subheadline).foregroundStyle(Brand.violetDeep).accessibilityLabel("Due") }
                else { Label("\(p.timesSeen)", systemImage: "eye.fill").font(.subheadline).accessibilityLabel("Seen \(p.timesSeen) times") }
            }
        }
    }
}

struct WordDetail: View {
    let entry: VocabEntry
    @ObservedObject var session: FeedSession
    @ObservedObject var wordBook: WordBook

    var body: some View {
        let p = wordBook.progress(entry.id)
        List {
            Section {
                VStack(spacing: 8) {
                    Text(entry.emoji).font(.system(size: 56))
                    if entry.kanji != nil { Text(entry.kana).font(.title3).foregroundStyle(Brand.violetDeep) }
                    Text(entry.written).font(.system(size: 48, weight: .heavy, design: .rounded))
                    Text(entry.romaji).font(.title3)
                    Text(entry.meaning).font(.headline)
                    Button {
                        Speech.shared.say(entry.kana)
                        wordBook.recordHeard(entry.id)
                    } label: {
                        Label("Hear it", systemImage: "speaker.wave.2.fill").font(.headline).padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.violet)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            if let p {
                Section {
                    LabeledContent { BoxDots(box: p.box) } label: { Label("Strength", systemImage: "chart.bar.fill") }
                    LabeledContent { Text("\(p.timesSeen)×") } label: { Label("Seen", systemImage: "eye.fill") }
                    LabeledContent { Text("\(p.timesHeard)×") } label: { Label("Heard", systemImage: "ear.fill") }
                    LabeledContent { Text("\(p.correct) ✓  \(p.wrong) ✗") } label: { Label("Answers", systemImage: "checklist") }
                    // Never show a confident recall % for a word no check has tested.
                    LabeledContent { Text(p.correct + p.wrong == 0 ? "–" : "≈\(Int((p.recallNow * 100).rounded()))%") } label: { Label("Recall", systemImage: "brain.head.profile") }
                    LabeledContent { Text(p.isDue ? "Now" : p.due.formatted(.relative(presentation: .named))) } label: { Label("Next check", systemImage: "clock.fill") }
                    LabeledContent {
                        Image(systemName: p.isLearned ? "checkmark.seal.fill" : p.correct == 0 && (p.stability ?? 0) >= 2 ? "hand.raised.fill" : "hourglass")
                            .foregroundStyle(p.isLearned ? Brand.success : Brand.warn)
                    } label: { Label(p.isLearned ? "Learned" : "Learning", systemImage: "graduationcap.fill") }
                    if p.isKnown {
                        Button("I don't know it after all") { wordBook.markKnown(entry.id, false) }
                    } else {
                        Button("I already know this") { wordBook.claimKnown(entry.id) }
                    }
                } header: { Text("Progress") }
                if !p.contexts.isEmpty {
                    Section("Where you met it") {
                        ForEach(p.contexts, id: \.self) { c in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(highlighted(c.line, entry: entry, vocab: session.vocab))
                                if let ja = c.japaneseLine { Text(ja).font(.subheadline) }
                                Label("\(c.title.isEmpty ? "YouTube Short" : c.title) · \(c.date.formatted(.relative(presentation: .named)))", systemImage: "play.rectangle.fill")
                                    .font(.subheadline).foregroundStyle(Brand.violetDeep).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.written)
        .navigationBarTitleDisplayMode(.inline)
    }
}
