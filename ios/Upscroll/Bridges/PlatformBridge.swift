import Foundation

/// One caption line with timing, in seconds.
struct Cue: Codable, Hashable {
    let start: Double
    let end: Double
    let text: String
}

struct CaptionTrackInfo: Codable, Hashable {
    let languageCode: String
    let kind: String
    let name: String
    let isTranslatable: Bool
}

struct VideoInfo: Codable, Hashable {
    let videoId: String
    let title: String
    let author: String
    let lengthSeconds: Double
    let description: String
    let tracks: [CaptionTrackInfo]
    let source: String
}

enum CaptionRole: String, Codable {
    case source      // the language the video speaks / its English captions
    case japanese    // auto-translated (tlang=ja) or native Japanese track
    case none
}

struct CaptionPayload: Codable {
    let videoId: String
    let role: CaptionRole
    let languageCode: String?
    let kind: String?
    let cues: [Cue]
    let status: Int?
    let empty: Bool?
    let usedPot: Bool?
    let note: String?
}

struct TickPayload: Codable {
    let videoId: String
    let currentTime: Double
    let duration: Double
    let paused: Bool
    /// The active Short is a sponsored ad (scripted marketing copy: no word cards there).
    var ad: Bool? = nil
    /// YouTube auto-dubbed this Short (audio may not match the original captions).
    var dub: Bool? = nil
}

/// Platform-neutral events. Each platform bridge turns its page's messages into these,
/// so overlays, lessons and SRS never know which platform they're running on.
enum BridgeEvent {
    case video(VideoInfo)
    case captions(CaptionPayload)
    case tick(TickPayload)
    case log(String)
}

protocol PlatformBridge {
    /// Display name, e.g. "YouTube Shorts".
    var name: String { get }
    /// Page the feed browser opens.
    var startURL: URL { get }
    /// JavaScript injected at document start in every frame of the main page.
    var userScriptSource: String { get }
    /// Name of the WKScriptMessageHandler the script posts to.
    var messageHandlerName: String { get }
    /// Decode one raw message from the page.
    func decode(type: String, json: String) -> BridgeEvent?
}

extension PlatformBridge {
    var messageHandlerName: String { "ds" }
}
