import SwiftUI

/// Phase 0 diagnostics: caption hit rates, current video state, logs and a JSON report export.
struct DebugTab: View {
    @ObservedObject var session: FeedSession
    @State private var exportURL: URL?

    var body: some View {
        let s = session.stats
        List {
            Section("Go / no-go (target: most Shorts have EN + JA lines)") {
                row("Videos seen", "\(s.videosSeen)")
                row("Had caption track list", "\(s.withTrackList)")
                row("English/source lines", "\(s.withSourceCues)  (\(pct(s.sourceHitRate)))")
                row("Japanese lines", "\(s.withJapaneseCues)  (\(pct(s.japaneseHitRate)))")
                row("Empty caption responses", "\(s.emptyResponses)")
                row("Recovered via player token", "\(s.potRecovered)")
                row("Videos with learning words", "\(s.withTargets)")
                row("Learning words placed", "\(s.targetsTotal)")
                row("Videos picked by Jev", "\(s.pickedByJev)")
            }
            Section("Current video") {
                let r = session.currentRecord
                row("ID", session.currentVideoId ?? "–")
                row("Title", r?.info?.title ?? "–")
                row("Tracks", r?.info?.tracks.map { "\($0.languageCode)\($0.kind == "asr" ? "(asr)" : "")" }.joined(separator: ", ") ?? "–")
                row("Lines EN / JA", "\(r?.sourceCues.count ?? 0) / \(r?.japaneseCues.count ?? 0)")
                row("Picked by", r?.pickedBy ?? "–")
                row("Learning words", r?.targets.compactMap { session.vocab.byId[$0.entryId]?.kana }.joined(separator: ", ") ?? "–")
                row("Time", String(format: "%.1fs%@", session.currentTime, session.paused ? " (paused)" : ""))
            }
            Section {
                Button("Export report JSON") { exportURL = session.exportReport() }
                if let url = exportURL {
                    ShareLink(item: url) { Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up") }
                }
            }
            Section("Log") {
                ForEach(Array(session.logs.suffix(80).reversed().enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
        }
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
    }

    private func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
}
