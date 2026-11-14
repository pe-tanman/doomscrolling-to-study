import Foundation
import Combine
import UIKit

/// Saves learning progress to Supabase (table `progress`, one JSON row per user) and merges it back.
/// - Sign-in / launch: download → merge into the phone's data → upload the merged copy.
/// - While using the app: changes are uploaded 15 s after they settle, and when the app goes to the background.
/// Local files stay the source of truth offline; the cloud copy is a backup that also moves you to a new phone.
@MainActor
final class CloudSync: ObservableObject {
    static let shared = CloudSync()

    struct Snapshot: Codable {
        var version = 1
        var savedAt = Date()
        var words: WordBook.CloudPart
        var journey: JourneyStore.CloudPart
        var rewards: Rewards.CloudPart
        var settings: LearnerSettings?
    }

    enum Status: Equatable { case idle, syncing, synced(Date), failed(String) }
    @Published private(set) var status: Status = .idle

    private weak var wordBook: WordBook?
    private weak var journey: JourneyStore?
    private weak var session: FeedSession?
    private var bag: Set<AnyCancellable> = []
    private var uploadTask: Task<Void, Never>?
    private var applying = false

    private init() {}

    /// Debug / UI-test launches seed fake progress; it must never reach (or be merged with) the account's cloud copy.
    static let disabled: Bool = {
        let flags: Set<String> = ["-lab", "-dashboard", "-demoJourney", "-demoLesson", "-resetJourney", "-resetWords",
                                  "-seedReview", "-seedReviewSet", "-kanaKnown", "-forceNonverbal", "-forceOriginal",
                                  "-autoReveal", "-onboarding", "-recap", "-startURL", "-fakeSendFailure", "-previewCheckEmail"]
        return ProcessInfo.processInfo.arguments.contains { flags.contains($0) }
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }()

    /// Called once at launch with the app's stores.
    func attach(wordBook: WordBook, journey: JourneyStore, session: FeedSession) {
        self.wordBook = wordBook; self.journey = journey; self.session = session
        Publishers.Merge3(wordBook.objectWillChange.map { _ in () },
                          journey.objectWillChange.map { _ in () },
                          Rewards.shared.objectWillChange.map { _ in () })
            .sink { [weak self] in self?.scheduleUpload() }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in Task { await self?.upload() } }
            .store(in: &bag)
        if SupabaseAuth.shared.isSignedIn { Task { await syncNow() } }
    }

    // MARK: Sync

    /// Download → merge → upload. Safe to call any time; does nothing when signed out.
    func syncNow() async {
        guard !Self.disabled, SupabaseAuth.shared.isSignedIn, let wordBook, let journey else { return }
        status = .syncing
        do {
            let token = try await SupabaseAuth.shared.accessToken()
            if let remote = try await download(token: token) {
                applying = true
                let freshPhone = wordBook.words.isEmpty
                wordBook.cloudMerge(remote.words)
                journey.cloudMerge(remote.journey)
                Rewards.shared.cloudMerge(remote.rewards)
                // A brand-new phone takes your saved settings; otherwise this phone's settings stay.
                if freshPhone, let s = remote.settings { session?.settings = s }
                applying = false
            }
            try await push(token: token)
            status = .synced(Date())
        } catch {
            applying = false
            status = .failed(error.localizedDescription)
        }
    }

    private func scheduleUpload() {
        guard !Self.disabled, !applying, SupabaseAuth.shared.isSignedIn else { return }
        uploadTask?.cancel()
        uploadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await self?.upload()
        }
    }

    func upload() async {
        guard !Self.disabled, SupabaseAuth.shared.isSignedIn, wordBook != nil else { return }
        do {
            let token = try await SupabaseAuth.shared.accessToken()
            try await push(token: token)
            status = .synced(Date())
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: REST

    private static let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private func snapshot() -> Snapshot? {
        guard let wordBook, let journey else { return nil }
        return Snapshot(words: wordBook.cloudExport(), journey: journey.cloudExport(),
                        rewards: Rewards.shared.cloudExport(), settings: session?.settings)
    }

    private func push(token: String) async throws {
        guard let uid = SupabaseAuth.shared.session?.userId, let snap = snapshot() else { return }
        struct Row: Encodable { let user_id: String; let data: Snapshot; let version: Int; let device: String }
        let body = try Self.enc.encode([Row(user_id: uid, data: snap, version: snap.version, device: UIDevice.current.model)])
        _ = try await SupabaseAuth.shared.rest("progress?on_conflict=user_id", method: "POST", body: body, token: token,
                                               headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    private func download(token: String) async throws -> Snapshot? {
        guard let uid = SupabaseAuth.shared.session?.userId else { return nil }
        let data = try await SupabaseAuth.shared.rest("progress?user_id=eq.\(uid)&select=data", method: "GET", token: token)
        struct Row: Decodable { let data: Snapshot }
        return try Self.dec.decode([Row].self, from: data).first?.data
    }

    /// Removes the cloud copy only (this phone keeps everything).
    func deleteCloudCopy() async throws {
        guard let uid = SupabaseAuth.shared.session?.userId else { return }
        let token = try await SupabaseAuth.shared.accessToken()
        _ = try await SupabaseAuth.shared.rest("progress?user_id=eq.\(uid)", method: "DELETE", token: token)
        status = .idle
    }
}
