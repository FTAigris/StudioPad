import Foundation

enum BroadcastConstants {
    static let streamURLKey = "StudioPadStreamURL"
    static let videoBitRateKey = "StudioPadVideoBitRate"
    static let framesPerSecondKey = "StudioPadFramesPerSecond"
    static let displayURL = URL(string: "https://localhost/studiopad")!
    static let configurationRelayPort: UInt16 = 49_321
}

struct BroadcastConfigurationPayload: Codable, Sendable {
    let streamURL: String
    let videoBitRate: Int
    let framesPerSecond: Int

    var validatedURL: URL? {
        guard let url = URL(string: streamURL),
              url.scheme == "rtmp" || url.scheme == "rtmps" else { return nil }
        return url
    }

    var safeVideoBitRate: Int {
        min(max(videoBitRate, 2_000_000), 8_000_000)
    }

    var safeFramesPerSecond: Int {
        min(max(framesPerSecond, 24), 60)
    }
}
