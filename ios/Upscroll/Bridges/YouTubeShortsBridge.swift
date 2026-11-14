import Foundation

struct YouTubeShortsBridge: PlatformBridge {
    let name = "YouTube Shorts"
    let startURL = URL(string: "https://m.youtube.com/shorts")!

    var userScriptSource: String {
        guard let url = Bundle.main.url(forResource: "youtube-shorts-bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("youtube-shorts-bridge.js missing from bundle")
            return ""
        }
        return source
    }

    private let decoder = JSONDecoder()

    func decode(type: String, json: String) -> BridgeEvent? {
        let data = Data(json.utf8)
        switch type {
        case "video":
            return (try? decoder.decode(VideoInfo.self, from: data)).map(BridgeEvent.video)
        case "captions":
            return (try? decoder.decode(CaptionPayload.self, from: data)).map(BridgeEvent.captions)
        case "tick":
            return (try? decoder.decode(TickPayload.self, from: data)).map(BridgeEvent.tick)
        case "log":
            return .log(json)
        default:
            return .log("unknown message type \(type): \(json)")
        }
    }
}
