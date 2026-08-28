import Combine
import CoreGraphics
import Foundation

enum StreamDestination: String, CaseIterable, Identifiable {
    case youtube = "YouTube"
    case twitch = "Twitch"
    case kick = "Kick"
    case custom = "Otro RTMP"

    var id: String { rawValue }

    var guidance: String {
        switch self {
        case .youtube:
            return "Copia la URL del servidor y la clave desde YouTube Studio."
        case .twitch:
            return "Copia el servidor de ingestión y tu clave desde el panel de Twitch."
        case .kick:
            return "Copia la URL y la clave RTMP desde el panel de creador de Kick."
        case .custom:
            return "Introduce una URL RTMP o RTMPS y la clave entregada por el servicio."
        }
    }
}

enum StudioResolutionPreset: String, CaseIterable, Identifiable {
    case fullHD = "1920 × 1080"
    case hd = "1280 × 720"
    case verticalFullHD = "1080 × 1920"
    case custom = "Personalizada"

    var id: String { rawValue }

    var dimensions: (width: Int, height: Int)? {
        switch self {
        case .fullHD: return (1920, 1080)
        case .hd: return (1280, 720)
        case .verticalFullHD: return (1080, 1920)
        case .custom: return nil
        }
    }
}

@MainActor
final class StreamConfiguration: ObservableObject {
    static let shared = StreamConfiguration()

    private enum Keys {
        static let destination = "stream.destination"
        static let serverURL = "stream.serverURL"
        static let streamKey = "stream.key"
        static let bitrate = "stream.bitrate"
        static let framesPerSecond = "stream.fps"
        static let outputWidth = "studio.output.width"
        static let outputHeight = "studio.output.height"
    }

    @Published var destination: StreamDestination {
        didSet { defaults.set(destination.rawValue, forKey: Keys.destination) }
    }

    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: Keys.serverURL) }
    }

    @Published var streamKey: String {
        didSet { KeychainStore.set(streamKey, forKey: Keys.streamKey) }
    }

    @Published var bitrate: Int {
        didSet { defaults.set(bitrate, forKey: Keys.bitrate) }
    }

    @Published var framesPerSecond: Int {
        didSet { defaults.set(framesPerSecond, forKey: Keys.framesPerSecond) }
    }

    @Published var outputWidth: Int {
        didSet { defaults.set(outputWidth, forKey: Keys.outputWidth) }
    }

    @Published var outputHeight: Int {
        didSet { defaults.set(outputHeight, forKey: Keys.outputHeight) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedDestination = defaults.string(forKey: Keys.destination)
            .flatMap(StreamDestination.init(rawValue:))
        destination = savedDestination ?? .youtube
        serverURL = defaults.string(forKey: Keys.serverURL) ?? ""
        let legacyStreamKey = defaults.string(forKey: Keys.streamKey)
        streamKey = KeychainStore.string(forKey: Keys.streamKey) ?? legacyStreamKey ?? ""

        let savedBitrate = defaults.integer(forKey: Keys.bitrate)
        bitrate = savedBitrate == 0 ? 4_000_000 : savedBitrate

        let savedFPS = defaults.integer(forKey: Keys.framesPerSecond)
        framesPerSecond = savedFPS == 0 ? 30 : savedFPS

        let savedWidth = defaults.integer(forKey: Keys.outputWidth)
        outputWidth = savedWidth == 0 ? 1920 : savedWidth

        let savedHeight = defaults.integer(forKey: Keys.outputHeight)
        outputHeight = savedHeight == 0 ? 1080 : savedHeight

        if KeychainStore.string(forKey: Keys.streamKey) == nil, !streamKey.isEmpty {
            KeychainStore.set(streamKey, forKey: Keys.streamKey)
        }
        defaults.removeObject(forKey: Keys.streamKey)
    }

    var streamURL: URL? {
        let cleanServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanKey = streamKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanServer.isEmpty, !cleanKey.isEmpty else { return nil }
        guard cleanServer.hasPrefix("rtmp://") || cleanServer.hasPrefix("rtmps://") else {
            return nil
        }
        return URL(string: cleanServer + "/" + cleanKey)
    }

    var isValid: Bool { streamURL != nil }

    var resolutionPreset: StudioResolutionPreset {
        get {
            StudioResolutionPreset.allCases.first(where: { preset in
                guard let dimensions = preset.dimensions else { return false }
                return dimensions.width == outputWidth && dimensions.height == outputHeight
            }) ?? .custom
        }
        set {
            guard let dimensions = newValue.dimensions else { return }
            outputWidth = dimensions.width
            outputHeight = dimensions.height
        }
    }

    var outputSize: CGSize {
        CGSize(
            width: CGFloat(normalized(outputWidth, minimum: 320, maximum: 3840)),
            height: CGFloat(normalized(outputHeight, minimum: 240, maximum: 2160))
        )
    }

    var outputAspectRatio: CGFloat {
        outputSize.width / max(outputSize.height, 1)
    }

    func normalizeResolution() {
        outputWidth = Int(outputSize.width)
        outputHeight = Int(outputSize.height)
    }

    private func normalized(_ value: Int, minimum: Int, maximum: Int) -> Int {
        let clamped = min(max(value, minimum), maximum)
        return clamped.isMultiple(of: 2) ? clamped : clamped - 1
    }
}
