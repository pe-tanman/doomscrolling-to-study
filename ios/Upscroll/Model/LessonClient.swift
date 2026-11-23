import Foundation
import CryptoKit

/// Asks the lesson server (TypeSafe Jev) which caption words to teach in one Short.
/// The TypeSafe API key lives only on the server; the app sends captions + candidate swaps.
struct LessonRequest: Encodable {
    struct CueDTO: Encodable { let i: Int; let start: Double; let end: Double; let text: String; let ja: String? }
    struct CandidateDTO: Encodable {
        let cue: Int
        let entryId: String
        let word: String
        let kana: String
        let meaning: String
        let status: String
    }
    let videoId: String
    let title: String
    let wordsPerVideo: Int
    let playedTo: Double
    let cues: [CueDTO]
    let candidates: [CandidateDTO]
}

struct LessonResponse: Decodable {
    struct Target: Decodable { let entryId: String; let cue: Int }
    /// sense: the word has this meaning here; fits: Japanese really says it with this word here (not an idiom / word-for-word).
    struct Judged: Decodable { let cue: Int; let entryId: String; let word: String; let sense: Double?; let useful: Double?; var fits: Double? = nil }
    let videoId: String
    let targets: [Target]
    let judged: [Judged]?
    let model: String?
    let ms: Int?
    let cached: Bool?
}

enum LessonClient {
    static var baseURL: URL? {
        #if DEBUG
        // `-lessonServer http://localhost:8787/` to try server changes before deploying.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-lessonServer"), i + 1 < args.count, let u = URL(string: args[i + 1]) { return u }
        #endif
        guard let s = Bundle.main.object(forInfoDictionaryKey: "LessonServerURL") as? String,
              !s.isEmpty, !s.contains("$(") else { return nil }
        return URL(string: s)
    }

    /// Request signing: the server only answers requests signed with the app's secret.
    /// HMAC-SHA256(secret, "ts\nnonce\nbody"); a fresh nonce per request blocks replays.
    private static let secret: SymmetricKey? = {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "DSAppSecret") as? String,
              !s.isEmpty, !s.contains("$(") else { return nil }
        return SymmetricKey(data: Data(s.utf8))
    }()

    private static func sign(_ r: inout URLRequest, body: Data) {
        r.setValue(DeviceID.value, forHTTPHeaderField: "x-ds-device")   // server-side daily limits per install
        guard let key = secret else { return }
        let ts = String(Int(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        var msg = Data("\(ts)\n\(nonce)\n".utf8)
        msg.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: msg, using: key)
        r.setValue(ts, forHTTPHeaderField: "x-ds-ts")
        r.setValue(nonce, forHTTPHeaderField: "x-ds-nonce")
        r.setValue(mac.map { String(format: "%02x", $0) }.joined(), forHTTPHeaderField: "x-ds-sig")
    }

    static func pick(_ req: LessonRequest) async throws -> LessonResponse {
        guard Plan.consume(.smartPicks) else { throw Plan.LimitReached(feature: .smartPicks) }
        return try await post("api/lesson", req)
    }

    static func picture(_ req: PictureRequest) async throws -> PictureResponse {
        guard Plan.consume(.pictureQuestions) else { throw Plan.LimitReached(feature: .pictureQuestions) }
        return try await post("api/picture", req, timeout: 15)
    }

    /// Natural Japanese speech (Gemini 3.8 Flash TTS on the server) as WAV bytes.
    static func speech(_ text: String) async throws -> Data {
        struct Body: Encodable { let text: String }
        guard Plan.consume(.naturalVoice) else { throw Plan.LimitReached(feature: .naturalVoice) }
        return try await raw("api/tts", Body(text: text), timeout: 8)
    }

    /// Which caption lines of a Short are worth learning as whole phrases (Jev: learnable × good translation).
    static func phrase(_ req: PhraseRequest) async throws -> PhraseResponse {
        guard Plan.consume(.smartPicks) else { throw Plan.LimitReached(feature: .smartPicks) }
        return try await post("api/phrase", req, timeout: 8)
    }

    /// Grammar chunks in a Short's Japanese lines (Jev: right grammar? good translation? only one right answer?).
    static func grammar(_ req: GrammarRequest) async throws -> GrammarResponse {
        guard Plan.consume(.smartPicks) else { throw Plan.LimitReached(feature: .smartPicks) }
        return try await post("api/grammar", req, timeout: 8)
    }

    /// The learner's personal direction: next place, focus skill, phrase priority (Jev).
    static func path(_ req: PathRequest) async throws -> PathResponse {
        try await post("api/path", req, timeout: 10)
    }

    /// The special lesson video catalog (public, read-only).
    static func lessons() async throws -> LessonCatalog {
        guard let base = baseURL else { throw URLError(.badURL) }
        var r = URLRequest(url: base.appendingPathComponent("api/lessons"))
        r.timeoutInterval = 8
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(LessonCatalog.self, from: data)
    }

    private static func post<In: Encodable, Out: Decodable>(_ path: String, _ req: In, timeout: TimeInterval = 10) async throws -> Out {
        try JSONDecoder().decode(Out.self, from: try await raw(path, req, timeout: timeout))
    }

    private static func raw<In: Encodable>(_ path: String, _ req: In, timeout: TimeInterval = 10) async throws -> Data {
        guard let base = baseURL else { throw URLError(.badURL) }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.timeoutInterval = timeout
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        let body = try JSONEncoder().encode(req)
        r.httpBody = body
        sign(&r, body: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw NSError(domain: "Lesson", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(msg)"])
        }
        return data
    }
}



/// Shorts with no talking: a screenshot of the video and the word candidates Jev checks it against.
struct PictureRequest: Encodable {
    struct Image: Encodable { let format: String; let data_base64: String }
    struct Candidate: Encodable { let entryId: String; let en: String; let status: String }
    let videoId: String
    let title: String
    let image: Image
    let candidates: [Candidate]
    let colors: [Candidate]
    /// Words asked about in recent picture questions (the server skips them when it can).
    let avoid: [String]
}

struct PictureResponse: Decodable {
    struct Box: Decodable { let top: Double; let bottom: Double; let left: Double; let right: Double; let confidence: Double }
    struct Color: Decodable { let entryId: String; let confidence: Double }
    struct Thing: Decodable { let entryId: String; let p: Double; let box: Box?; let color: Color? }
    let videoId: String
    let things: [Thing]
    let visible: [String]
    let absent: [String]
    let model: String?
    let ms: Int?
}


/// Caption lines with YouTube's Japanese, for whole-phrase picks.
struct PhraseRequest: Encodable {
    struct Line: Encodable { let i: Int; let en: String; let ja: String }
    let videoId: String
    let title: String
    let goal: String
    let lines: [Line]
    /// What the learner already knows (so Jev picks a next step, not a leap).
    var learner: LearnerDTO? = nil
}

struct LearnerDTO: Encodable {
    let stage: String
    let wordsLearned: Int
    let known: [String]
}

struct GrammarRequest: Encodable {
    /// A word of the line with its meaning; known = the learner has answered it right before.
    struct Word: Encodable { let ja: String; let meaning: String; let known: Bool }
    struct Line: Encodable { let i: Int; let en: String; let ja: String; let words: [Word] }
    struct Candidate: Encodable {
        let line: Int
        let point: String
        let title: String
        let meaning: String
        let piece: String
        let before: String
        let after: String
        let distractors: [String]
        let status: String
    }
    let videoId: String
    let title: String
    let learner: LearnerDTO
    let lines: [Line]
    let candidates: [Candidate]
}

struct GrammarResponse: Decodable {
    struct Pick: Decodable { let line: Int; let point: String; let piece: String; let distractors: [String]; let fit: Double? }
    let videoId: String
    let picks: [Pick]
    let model: String?
}

struct PhraseResponse: Decodable {
    struct Pick: Decodable { let i: Int; let learn: Double?; let ja: Double? }
    let videoId: String
    let picks: [Pick]
    let model: String?
}

struct PathRequest: Encodable {
    struct SkillResult: Encodable { let right: Int; let wrong: Int; let dots: Int }
    struct PlaceDTO: Encodable { let id: String; let name: String; let summary: String; let canDos: [String]; let done: Int; let total: Int }
    struct PhraseDTO: Encodable { let id: String; let place: String; let meaning: String; let example: String }
    let goal: String
    let level: String
    let wordsLearned: Int
    let interests: [String]
    let skills: [String: SkillResult]
    let speakingOff: Bool
    /// Ladder stage and grammar the learner has right (chunks, patterns…).
    var stage: String? = nil
    var grammarKnown: [String] = []
    let places: [PlaceDTO]
    let phrases: [PhraseDTO]
}

struct PathResponse: Decodable {
    let order: [String]
    let next: String?
    let nextConfidence: Double?
    let focus: String?
    let phrasePriority: [String]
    let model: String?
}

/// A random id for this install, kept in the Keychain (this phone only), so the server's daily limits
/// follow the install rather than resetting on reinstall. Not linked to the person or the Apple ID.
enum DeviceID {
    static let value: String = {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.upscroll.app.device",
                                kSecAttrAccount as String: "id", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8) {
            return s
        }
        let id = UUID().uuidString
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.upscroll.app.device",
                                  kSecAttrAccount as String: "id", kSecValueData as String: Data(id.utf8),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(add as CFDictionary, nil)
        return id
    }()
}
