import HaishinKit
import ReplayKit
import RTMPHaishinKit
import VideoToolbox

final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {
    private let mixer = MediaMixer(
        captureSessionMode: .manual,
        multiTrackAudioMixingEnabled: true
    )
    private var session: (any Session)?
    private var configurationReceiver: BroadcastConfigurationReceiver?
    private var configurationTimeout: Task<Void, Never>?
    private var needsVideoConfiguration = true
    private var isReady = false
    private var videoBitRate = 4_000_000
    private var framesPerSecond = 30

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        if let streamURLString = setupInfo?[BroadcastConstants.streamURLKey] as? String,
           let streamURL = Self.validatedStreamURL(streamURLString) {
            videoBitRate = (setupInfo?[BroadcastConstants.videoBitRateKey] as? NSNumber)?.intValue
                ?? 4_000_000
            framesPerSecond = (setupInfo?[BroadcastConstants.framesPerSecondKey] as? NSNumber)?.intValue
                ?? 30
            Task { await startBroadcast(to: streamURL) }
            return
        }

        do {
            let receiver = try BroadcastConfigurationReceiver { [weak self] payload in
                guard let self, let streamURL = payload.validatedURL else { return }
                configurationTimeout?.cancel()
                configurationTimeout = nil
                configurationReceiver = nil
                videoBitRate = payload.safeVideoBitRate
                framesPerSecond = payload.safeFramesPerSecond
                Task { await startBroadcast(to: streamURL) }
            }
            configurationReceiver = receiver
            receiver.start()

            configurationTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled, let self else { return }
                configurationReceiver?.stop()
                configurationReceiver = nil
                finishBroadcastWithError(Self.error(
                    "Abre StudioPad, configura la transmisión e inténtalo nuevamente."
                ))
            }
        } catch {
            finishBroadcastWithError(Self.error("No se pudo recibir la configuración local."))
        }
    }

    override func broadcastPaused() {
        // ReplayKit deja de entregar muestras mientras la emisión está pausada.
    }

    override func broadcastResumed() {
        // No hace falta reconstruir la conexión al reanudar.
    }

    override func broadcastFinished() {
        configurationTimeout?.cancel()
        configurationTimeout = nil
        configurationReceiver?.stop()
        configurationReceiver = nil
        Task {
            isReady = false
            try? await session?.close()
            if let session {
                await mixer.removeOutput(session.stream)
            }
            await mixer.stopRunning()
            session = nil
        }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard isReady else { return }

        switch sampleBufferType {
        case .video:
            if needsVideoConfiguration {
                needsVideoConfiguration = false
                Task { await configureVideo(from: sampleBuffer) }
            }
            Task { await mixer.append(sampleBuffer) }

        case .audioMic:
            guard sampleBuffer.dataReadiness == .ready else { return }
            Task { await mixer.append(sampleBuffer, track: 0) }

        case .audioApp:
            guard sampleBuffer.dataReadiness == .ready else { return }
            Task { await mixer.append(sampleBuffer, track: 1) }

        @unknown default:
            break
        }
    }

    private func startBroadcast(to url: URL) async {
        do {
            await SessionBuilderFactory.shared.register(RTMPSessionFactory())

            guard let newSession = try await SessionBuilderFactory.shared.make(url)
                .setMode(.publish)
                .build() else {
                throw Self.error("No se pudo crear la sesión de transmisión.")
            }
            session = newSession

            var mixerVideoSettings = await mixer.videoMixerSettings
            mixerVideoSettings.mode = .passthrough
            await mixer.setVideoMixerSettings(mixerVideoSettings)

            var mixerAudioSettings = await mixer.audioMixerSettings
            var microphoneTrack = mixerAudioSettings.tracks[0] ?? .init()
            microphoneTrack.volume = 1.0
            mixerAudioSettings.tracks[0] = microphoneTrack
            var applicationTrack = mixerAudioSettings.tracks[1] ?? .init()
            applicationTrack.volume = 0.65
            mixerAudioSettings.tracks[1] = applicationTrack
            await mixer.setAudioMixerSettings(mixerAudioSettings)

            await newSession.stream.setVideoInputBufferCounts(5)
            var audioSettings = await newSession.stream.audioSettings
            audioSettings.bitRate = 128_000
            try await newSession.stream.setAudioSettings(audioSettings)

            await mixer.addOutput(newSession.stream)
            await mixer.startRunning()
            try await newSession.connect {
                // El estado de red se gestiona dentro de HaishinKit.
            }
            isReady = true
        } catch {
            finishBroadcastWithError(Self.error(error.localizedDescription))
        }
    }

    private func configureVideo(from sampleBuffer: CMSampleBuffer) async {
        guard let session,
              let dimensions = sampleBuffer.formatDescription?.dimensions else { return }

        var videoSettings = await session.stream.videoSettings
        videoSettings.videoSize = CGSize(
            width: CGFloat(dimensions.width),
            height: CGFloat(dimensions.height)
        )
        videoSettings.bitRate = videoBitRate
        videoSettings.expectedFrameRate = Float64(framesPerSecond)
        videoSettings.profileLevel = kVTProfileLevel_H264_Baseline_AutoLevel as String
        try? await session.stream.setVideoSettings(videoSettings)
    }

    private static func error(_ description: String) -> NSError {
        NSError(
            domain: "StudioPad.ScreenBroadcast",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    private static func validatedStreamURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme == "rtmp" || url.scheme == "rtmps" else { return nil }
        return url
    }
}
