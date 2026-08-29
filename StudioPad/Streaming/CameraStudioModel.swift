@preconcurrency import AVFoundation
import Combine
import HaishinKit
import ImageIO
import Photos
import RTMPHaishinKit
import UIKit
import VideoToolbox

@MainActor
final class CameraStudioModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case connecting
        case live
        case stopping

        var label: String {
            switch self {
            case .idle: return "Lista"
            case .preparing: return "Preparando cámara"
            case .connecting: return "Conectando"
            case .live: return "En directo"
            case .stopping: return "Deteniendo"
            }
        }
    }

    @Published private(set) var status: Status = .preparing
    @Published private(set) var isMuted = false
    @Published private(set) var isRecording = false
    @Published private(set) var cameraLabel = "Trasera"
    @Published var errorMessage: String?

    private let captureMixer = MediaMixer()
    private let programMixer = MediaMixer(
        captureSessionMode: .manual,
        multiTrackAudioMixingEnabled: true
    )
    private lazy var programBridge = ProgramMixerBridge(target: programMixer)
    private var session: (any Session)?
    private var recorder: StreamRecorder?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isPrepared = false
    private var preparedURL: URL?
    private var outputSize = CGSize(width: 1920, height: 1080)
    private var currentProgramScene: StudioScene?
    private var hasExternalOutput = false
    @ScreenActor private var activeProgramObjects: [ScreenObject] = []
    @ScreenActor private var imageGalleryStates: [ProgramImageGalleryState] = []
    @ScreenActor private var mediaStates: [ProgramMediaState] = []
    @ScreenActor private var programAudioPlayers: [ProgramAudioSourcePlayer] = []
    @ScreenActor private var programAnimationTask: Task<Void, Never>?

    var isLive: Bool { status == .live }
    var canStart: Bool { status == .idle }

    func attachPreview(_ view: MTHKView) {
        Task { await captureMixer.addOutput(view) }
    }

    func detachPreview(_ view: MTHKView) {
        Task { await captureMixer.removeOutput(view) }
    }

    func prepare(using configuration: StreamConfiguration) async {
        guard !isPrepared else { return }
        status = .preparing

        do {
            try await requestCapturePermissions()
            try configureAudioSession()
            try await attachDevices()
            try await configureVideo(using: configuration)
            outputSize = configuration.outputSize
            await configureCanvas(size: outputSize)
            await captureMixer.addOutput(programBridge)
            await programMixer.startRunning()
            await captureMixer.startRunning()
            isPrepared = true
            status = .idle
        } catch {
            errorMessage = friendlyMessage(for: error)
            status = .idle
        }
    }

    func startStreaming(using configuration: StreamConfiguration) {
        Task {
            do {
                if !isPrepared {
                    await prepare(using: configuration)
                }
                guard isPrepared else {
                    throw StudioError.sessionUnavailable
                }
                guard let url = configuration.streamURL else {
                    throw StudioError.invalidStreamConfiguration
                }

                status = .connecting
                if session == nil || preparedURL != url {
                    try await rebuildSession(url: url, configuration: configuration)
                } else {
                    try await applyEncodingSettings(configuration)
                }

                guard let session else { throw StudioError.sessionUnavailable }
                try await session.connect {
                    // HaishinKit reports transport failures through the session state.
                }
                status = .live
                refreshIdleTimerPolicy()
            } catch {
                errorMessage = friendlyMessage(for: error)
                status = .idle
            }
        }
    }

    func stopStreaming() {
        Task {
            status = .stopping
            do {
                try await session?.close()
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
            status = .idle
            refreshIdleTimerPolicy()
        }
    }

    func flipCamera() {
        Task {
            let nextPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: nextPosition
            ) else {
                errorMessage = "No se encontró la cámara seleccionada."
                return
            }

            do {
                try await captureMixer.attachVideo(device) { unit in
                    unit.isVideoMirrored = nextPosition == .front
                }
                currentPosition = nextPosition
                cameraLabel = nextPosition == .front ? "Frontal" : "Trasera"
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    func toggleMute() {
        setMicrophoneMuted(!isMuted)
    }

    func setMicrophoneMuted(_ muted: Bool) {
        isMuted = muted
        Task {
            var settings = await captureMixer.audioMixerSettings
            var track = settings.tracks[0] ?? .init()
            track.isMuted = muted
            settings.tracks[0] = track
            await captureMixer.setAudioMixerSettings(settings)
        }
    }

    func setMicrophoneVolume(_ volume: Float) {
        Task {
            var settings = await captureMixer.audioMixerSettings
            var track = settings.tracks[0] ?? .init()
            track.volume = min(max(volume, 0), 1)
            settings.tracks[0] = track
            await captureMixer.setAudioMixerSettings(settings)
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func updateOutputConfiguration(using configuration: StreamConfiguration) {
        let newSize = configuration.outputSize
        let sizeChanged = newSize != outputSize
        outputSize = newSize
        let scene = currentProgramScene
        Task {
            try? await captureMixer.setFrameRate(Float64(configuration.framesPerSecond))
            try? await programMixer.setFrameRate(Float64(configuration.framesPerSecond))
            if sizeChanged {
                await configureCanvas(size: newSize)
                await rebuildProgramScene(scene, size: newSize)
            }
            try? await applyEncodingSettings(configuration)
        }
    }

    func updateProgramScene(_ scene: StudioScene?) {
        currentProgramScene = scene
        let size = outputSize
        Task { await rebuildProgramScene(scene, size: size) }
    }

    func setExternalOutputActive(_ active: Bool) {
        hasExternalOutput = active
        refreshIdleTimerPolicy()
    }

    func shutdown() {
        Task {
            if isRecording {
                await finishRecordingAndSave()
            }
            if let session {
                try? await session.close()
                await programMixer.removeOutput(session.stream)
            }
            session = nil
            preparedURL = nil
            await clearProgramObjects()
            await captureMixer.removeOutput(programBridge)
            await captureMixer.stopRunning()
            await programMixer.stopRunning()
            status = .idle
            isPrepared = false
            refreshIdleTimerPolicy()
        }
    }

    private func startRecording() {
        Task {
            do {
                let recorder = StreamRecorder()
                await programMixer.addOutput(recorder)
                try await recorder.startRecording()
                self.recorder = recorder
                isRecording = true
                refreshIdleTimerPolicy()
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    private func stopRecording() {
        Task { await finishRecordingAndSave() }
    }

    private func finishRecordingAndSave() async {
        guard let recorder else { return }
        do {
            let fileURL = try await recorder.stopRecording()
            await programMixer.removeOutput(recorder)
            self.recorder = nil
            isRecording = false
            refreshIdleTimerPolicy()

            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                throw StudioError.photoPermissionDenied
            }

            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: fileURL, options: nil)
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
            isRecording = false
            refreshIdleTimerPolicy()
        }
    }

    private func requestCapturePermissions() async throws {
        let cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        guard cameraAllowed else { throw StudioError.cameraPermissionDenied }

        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphoneAllowed else { throw StudioError.microphonePermissionDenied }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
        if #available(iOS 26.0, *) {
            options.insert(.allowBluetoothHFP)
        } else {
            options.insert(.allowBluetooth)
        }
        try audioSession.setCategory(
            .playAndRecord,
            mode: .videoRecording,
            options: options
        )
        try audioSession.setActive(true)
    }

    private func attachDevices() async throws {
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: currentPosition
        ) else {
            throw StudioError.cameraUnavailable
        }

        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw StudioError.microphoneUnavailable
        }

        await captureMixer.configuration { session in
            if session.isMultitaskingCameraAccessSupported {
                session.isMultitaskingCameraAccessEnabled = true
            }
        }

        try await captureMixer.attachVideo(camera) { unit in
            unit.isVideoMirrored = false
        }
        try await captureMixer.attachAudio(microphone)
    }

    private func configureVideo(using configuration: StreamConfiguration) async throws {
        try await captureMixer.setFrameRate(Float64(configuration.framesPerSecond))
        try await programMixer.setFrameRate(Float64(configuration.framesPerSecond))
        await captureMixer.setVideoOrientation(.landscapeRight)

        var captureSettings = await captureMixer.videoMixerSettings
        captureSettings.mode = .passthrough
        await captureMixer.setVideoMixerSettings(captureSettings)

        var programSettings = await programMixer.videoMixerSettings
        programSettings.mode = .offscreen
        await programMixer.setVideoMixerSettings(programSettings)
    }

    @ScreenActor
    private func configureCanvas(size: CGSize) async {
        await programMixer.screen.size = size
        await programMixer.screen.backgroundColor = UIColor.black.cgColor
    }

    private func rebuildSession(url: URL, configuration: StreamConfiguration) async throws {
        if let session {
            await programMixer.removeOutput(session.stream)
            try? await session.close()
        }

        guard let newSession = try await SessionBuilderFactory.shared.make(url)
            .setMode(.publish)
            .build() else {
            throw StudioError.sessionUnavailable
        }
        session = newSession
        preparedURL = url
        try await applyEncodingSettings(configuration)
        await programMixer.addOutput(newSession.stream)
    }

    private func applyEncodingSettings(_ configuration: StreamConfiguration) async throws {
        guard let session else { return }

        var videoSettings = await session.stream.videoSettings
        videoSettings.videoSize = outputSize
        videoSettings.bitRate = configuration.bitrate
        videoSettings.expectedFrameRate = Float64(configuration.framesPerSecond)
        videoSettings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String
        try await session.stream.setVideoSettings(videoSettings)

        var audioSettings = await session.stream.audioSettings
        audioSettings.bitRate = 128_000
        try await session.stream.setAudioSettings(audioSettings)
    }

    @ScreenActor
    private func rebuildProgramScene(_ scene: StudioScene?, size: CGSize) async {
        await clearProgramObjects()

        if let black = makeSolidImage(hex: "000000", size: size) {
            await addProgramImage(black, size: size)
        }

        let sources = scene?.sources.filter(\.isVisible) ?? []
        var nextAudioTrack: UInt8 = 1

        for source in sources.reversed() {
            switch source.kind {
            case .camera:
                let object = VideoTrackScreenObject()
                object.track = 0
                configureProgramObject(object, source: source)
                try? programMixer.screen.addChild(object)
                activeProgramObjects.append(object)

            case .color:
                let layerSize = sourceLayerSize(source)
                if let image = makeSolidImage(hex: source.colorHex, size: layerSize) {
                    await addProgramImage(image, source: source)
                }

            case .screen:
                let layerSize = sourceLayerSize(source)
                if let image = makeSolidImage(hex: "11141B", size: layerSize) {
                    await addProgramImage(image, source: source)
                }
                await addProgramText(
                    "Pantalla del iPad\nIníciala desde Capturar pantalla",
                    source: source
                )

            case .text:
                await addProgramText(source.text, source: source)

            case .image:
                guard let filename = source.assetPaths.first,
                      let url = StudioMediaLibrary.url(for: filename),
                      let image = makeCanvasImage(from: url, size: sourceLayerSize(source)) else { continue }
                await addProgramImage(image, source: source)

            case .imageGallery:
                let filenames = source.assetPaths.filter { StudioMediaLibrary.url(for: $0) != nil }
                guard let filename = filenames.first,
                      let url = StudioMediaLibrary.url(for: filename),
                      let image = makeCanvasImage(from: url, size: sourceLayerSize(source)) else { continue }
                let object = ImageScreenObject()
                object.cgImage = image
                configureProgramObject(object, source: source)
                try? programMixer.screen.addChild(object)
                activeProgramObjects.append(object)
                imageGalleryStates.append(
                    ProgramImageGalleryState(
                        object: object,
                        filenames: filenames,
                        index: 0,
                        interval: max(source.slideDuration, 1),
                        nextChange: Date.timeIntervalSinceReferenceDate + max(source.slideDuration, 1),
                        canvasSize: sourceLayerSize(source),
                        playbackMode: source.galleryPlaybackMode,
                        transitionDuration: source.galleryTransitionDuration,
                        isFinished: false,
                        transitionFromIndex: nil,
                        transitionToIndex: nil,
                        transitionStartedAt: nil
                    )
                )

            case .media, .mediaGallery:
                let urls = source.assetPaths.compactMap(StudioMediaLibrary.url(for:))
                guard let url = urls.first else { continue }
                let object = AssetScreenObject()
                object.videoGravity = .resizeAspect
                configureProgramObject(object, source: source)
                try? object.startReading(AVURLAsset(url: url))
                try? programMixer.screen.addChild(object)
                activeProgramObjects.append(object)
                mediaStates.append(
                    ProgramMediaState(
                        object: object,
                        urls: urls,
                        index: 0,
                        loops: source.loopsMedia,
                        isGallery: source.kind == .mediaGallery,
                        shuffles: source.shufflesPlaylist,
                        isFinished: false
                    )
                )

            case .audioOutput, .audioPlaylist:
                break
            }

            if source.kind.hasAudioTrack, nextAudioTrack < UInt8.max {
                await addProgramAudioSource(source, track: nextAudioTrack)
                nextAudioTrack += 1
            }
        }

        startProgramAnimationLoopIfNeeded()
    }
    @ScreenActor
    private func clearProgramObjects() async {
        programAnimationTask?.cancel()
        programAnimationTask = nil
        programAudioPlayers.forEach { $0.stop() }
        programAudioPlayers.removeAll()
        imageGalleryStates.removeAll()
        mediaStates.removeAll()
        for object in activeProgramObjects {
            if let asset = object as? AssetScreenObject {
                asset.cancelReading()
            }
            await programMixer.screen.removeChild(object)
        }
        activeProgramObjects.removeAll()
    }

    @ScreenActor
    private func startProgramAnimationLoopIfNeeded() {
        guard !imageGalleryStates.isEmpty || !mediaStates.isEmpty else { return }
        programAnimationTask = Task { @ScreenActor in
            while !Task.isCancelled {
                let now = Date.timeIntervalSinceReferenceDate

                for index in imageGalleryStates.indices where !imageGalleryStates[index].isFinished {
                    if let fromIndex = imageGalleryStates[index].transitionFromIndex,
                       let toIndex = imageGalleryStates[index].transitionToIndex,
                       let startedAt = imageGalleryStates[index].transitionStartedAt {
                        let duration = max(imageGalleryStates[index].transitionDuration, 0.001)
                        let progress = min(max((now - startedAt) / duration, 0), 1)
                        if let image = makeBlendedCanvasImage(
                            from: imageGalleryStates[index].filenames[fromIndex],
                            to: imageGalleryStates[index].filenames[toIndex],
                            size: imageGalleryStates[index].canvasSize,
                            progress: progress
                        ) {
                            imageGalleryStates[index].object.cgImage = image
                            imageGalleryStates[index].object.invalidateLayout()
                        }
                        if progress >= 1 {
                            imageGalleryStates[index].index = toIndex
                            imageGalleryStates[index].transitionFromIndex = nil
                            imageGalleryStates[index].transitionToIndex = nil
                            imageGalleryStates[index].transitionStartedAt = nil
                            imageGalleryStates[index].nextChange = now + imageGalleryStates[index].interval
                        }
                        continue
                    }

                    guard now >= imageGalleryStates[index].nextChange else { continue }
                    let state = imageGalleryStates[index]
                    let nextIndex: Int
                    switch state.playbackMode {
                    case .loop:
                        nextIndex = (state.index + 1) % state.filenames.count
                    case .once:
                        guard state.index + 1 < state.filenames.count else {
                            imageGalleryStates[index].isFinished = true
                            continue
                        }
                        nextIndex = state.index + 1
                    case .random:
                        nextIndex = state.filenames.indices
                            .filter { $0 != state.index }
                            .randomElement() ?? state.index
                    }

                    if state.transitionDuration <= 0 {
                        let filename = state.filenames[nextIndex]
                        if let url = StudioMediaLibrary.url(for: filename),
                           let image = makeCanvasImage(from: url, size: state.canvasSize) {
                            imageGalleryStates[index].object.cgImage = image
                            imageGalleryStates[index].object.invalidateLayout()
                        }
                        imageGalleryStates[index].index = nextIndex
                        imageGalleryStates[index].nextChange = now + state.interval
                    } else {
                        imageGalleryStates[index].transitionFromIndex = state.index
                        imageGalleryStates[index].transitionToIndex = nextIndex
                        imageGalleryStates[index].transitionStartedAt = now
                    }
                }

                for index in mediaStates.indices {
                    let state = mediaStates[index]
                    guard !state.isFinished, !state.object.isReading else { continue }

                    if state.isGallery {
                        let isLast = state.index == state.urls.count - 1
                        if isLast, !state.loops, !state.shuffles {
                            mediaStates[index].isFinished = true
                            continue
                        }
                        if state.shuffles, state.urls.count > 1 {
                            mediaStates[index].index = state.urls.indices
                                .filter { $0 != state.index }
                                .randomElement() ?? state.index
                        } else {
                            mediaStates[index].index = (state.index + 1) % state.urls.count
                        }
                        mediaStates[index].object.cancelReading()
                        try? mediaStates[index].object.startReading(
                            AVURLAsset(url: mediaStates[index].urls[mediaStates[index].index])
                        )
                    } else if state.loops {
                        try? mediaStates[index].object.startReading(
                            AVURLAsset(url: state.urls[state.index])
                        )
                    } else {
                        mediaStates[index].isFinished = true
                    }
                }

                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @ScreenActor
    private func addProgramImage(_ image: CGImage, size: CGSize) async {
        let object = ImageScreenObject()
        object.cgImage = image
        object.size = size
        try? await programMixer.screen.addChild(object)
        activeProgramObjects.append(object)
    }

    @ScreenActor
    private func addProgramImage(_ image: CGImage, source: StudioSource) async {
        let object = ImageScreenObject()
        object.cgImage = image
        configureProgramObject(object, source: source)
        try? programMixer.screen.addChild(object)
        activeProgramObjects.append(object)
    }

    @ScreenActor
    private func addProgramText(_ text: String, source: StudioSource) async {
        let object = TextScreenObject()
        object.string = text
        object.attributes = [
            .font: UIFont.boldSystemFont(ofSize: max(18, CGFloat(source.canvasHeight) * 0.07)),
            .foregroundColor: UIColor.white,
        ]
        object.horizontalAlignment = .center
        object.verticalAlignment = .middle
        configureProgramObject(object, source: source)
        try? programMixer.screen.addChild(object)
        activeProgramObjects.append(object)
    }

    @ScreenActor
    private func sourceLayerSize(_ source: StudioSource) -> CGSize {
        CGSize(
            width: max(CGFloat(source.canvasWidth), 1),
            height: max(CGFloat(source.canvasHeight), 1)
        )
    }

    @ScreenActor
    private func configureProgramObject(_ object: ScreenObject, source: StudioSource) {
        object.size = sourceLayerSize(source)
        object.horizontalAlignment = .left
        object.verticalAlignment = .top
        object.layoutMargin = UIEdgeInsets(
            top: CGFloat(source.canvasY),
            left: CGFloat(source.canvasX),
            bottom: 0,
            right: 0
        )
        object.invalidateLayout()
    }

    @ScreenActor
    private func addProgramAudioSource(_ source: StudioSource, track: UInt8) async {
        let allURLs = source.assetPaths.compactMap(StudioMediaLibrary.url(for:))
        let urls: [URL]
        switch source.kind {
        case .mediaGallery, .audioPlaylist:
            urls = allURLs
        default:
            urls = Array(allURLs.prefix(1))
        }
        guard !urls.isEmpty else { return }

        var settings = await programMixer.audioMixerSettings
        var trackSettings = settings.tracks[track] ?? .init()
        trackSettings.volume = Float(source.mediaVolume)
        trackSettings.isMuted = source.isMediaMuted
        settings.tracks[track] = trackSettings
        await programMixer.setAudioMixerSettings(settings)

        let player = ProgramAudioSourcePlayer(
            mixer: programMixer,
            track: track,
            urls: urls,
            loops: source.loopsMedia,
            shuffles: source.shufflesPlaylist,
            playbackRate: source.playbackRate
        )
        programAudioPlayers.append(player)
        player.start()
    }

    @ScreenActor
    private func makeSolidImage(hex: String, size: CGSize) -> CGImage? {
        guard let context = makeBitmapContext(size: size) else { return nil }
        context.setFillColor(UIColor(studioHex: hex).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    @ScreenActor
    private func makeCanvasImage(from url: URL, size: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = makeBitmapContext(size: size) else { return nil }

        let scale = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height))
        let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let rect = CGRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }

    @ScreenActor
    private func makeBlendedCanvasImage(
        from fromFilename: String,
        to toFilename: String,
        size: CGSize,
        progress: Double
    ) -> CGImage? {
        guard let fromURL = StudioMediaLibrary.url(for: fromFilename),
              let toURL = StudioMediaLibrary.url(for: toFilename),
              let fromImage = makeCanvasImage(from: fromURL, size: size),
              let toImage = makeCanvasImage(from: toURL, size: size),
              let context = makeBitmapContext(size: size) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        context.setAlpha(CGFloat(1 - progress))
        context.draw(fromImage, in: rect)
        context.setAlpha(CGFloat(progress))
        context.draw(toImage, in: rect)
        return context.makeImage()
    }

    @ScreenActor
    private func makeBitmapContext(size: CGSize) -> CGContext? {
        CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private func refreshIdleTimerPolicy() {
        UIApplication.shared.isIdleTimerDisabled = isLive || isRecording || hasExternalOutput
    }

    private func friendlyMessage(for error: Error) -> String {
        if let studioError = error as? StudioError {
            return studioError.localizedDescription
        }
        return "No se pudo completar la operación: \(error.localizedDescription)"
    }
}

private final class ProgramAudioSourcePlayer: @unchecked Sendable {
    private let mixer: MediaMixer
    private let track: UInt8
    private let urls: [URL]
    private let loops: Bool
    private let shuffles: Bool
    private let playbackRate: Double
    private var task: Task<Void, Never>?

    init(
        mixer: MediaMixer,
        track: UInt8,
        urls: [URL],
        loops: Bool,
        shuffles: Bool,
        playbackRate: Double
    ) {
        self.mixer = mixer
        self.track = track
        self.urls = urls
        self.loops = loops
        self.shuffles = shuffles
        self.playbackRate = max(playbackRate, 0.25)
    }

    func start() {
        stop()
        task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        guard !urls.isEmpty else { return }
        var index = 0

        while !Task.isCancelled {
            guard await play(urls[index]) else { return }
            guard !Task.isCancelled else { return }

            if shuffles, urls.count > 1 {
                index = urls.indices.filter { $0 != index }.randomElement() ?? index
            } else if index + 1 < urls.count {
                index += 1
            } else if loops {
                index = 0
            } else {
                return
            }
        }
    }

    private func play(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio),
              let audioTrack = tracks.first,
              let reader = try? AVAssetReader(asset: asset) else { return false }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return false }
        reader.add(output)
        guard reader.startReading() else { return false }

        var firstTimestamp: CMTime?
        let startedAt = Date.timeIntervalSinceReferenceDate

        while !Task.isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if firstTimestamp == nil { firstTimestamp = timestamp }
            if let firstTimestamp {
                let mediaElapsed = max(0, CMTimeGetSeconds(timestamp - firstTimestamp) / playbackRate)
                let realElapsed = Date.timeIntervalSinceReferenceDate - startedAt
                let delay = mediaElapsed - realElapsed
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            guard !Task.isCancelled else {
                reader.cancelReading()
                return false
            }
            await mixer.append(sampleBuffer, track: track)
        }
        return reader.status == .completed
    }
}

private final class ProgramMixerBridge: MediaMixerOutput, @unchecked Sendable {
    let videoTrackId: UInt8? = UInt8.max
    let audioTrackId: UInt8? = UInt8.max

    private let target: MediaMixer

    init(target: MediaMixer) {
        self.target = target
    }

    func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) async {}

    nonisolated func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task { [target] in await target.append(sampleBuffer) }
    }

    nonisolated func mixer(_ mixer: MediaMixer, didOutput buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        Task { [target] in await target.append(buffer, when: when) }
    }
}

private struct ProgramImageGalleryState {
    let object: ImageScreenObject
    let filenames: [String]
    var index: Int
    let interval: TimeInterval
    var nextChange: TimeInterval
    let canvasSize: CGSize
    let playbackMode: StudioGalleryPlaybackMode
    let transitionDuration: TimeInterval
    var isFinished: Bool
    var transitionFromIndex: Int?
    var transitionToIndex: Int?
    var transitionStartedAt: TimeInterval?
}

private struct ProgramMediaState {
    let object: AssetScreenObject
    let urls: [URL]
    var index: Int
    let loops: Bool
    let isGallery: Bool
    let shuffles: Bool
    var isFinished: Bool
}

private extension UIColor {
    convenience init(studioHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
            .scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

private enum StudioError: LocalizedError {
    case invalidStreamConfiguration
    case sessionUnavailable
    case cameraPermissionDenied
    case microphonePermissionDenied
    case cameraUnavailable
    case microphoneUnavailable
    case photoPermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidStreamConfiguration:
            return "Completa la URL RTMP y la clave en la pestaña Transmisión."
        case .sessionUnavailable:
            return "No se pudo crear la sesión de transmisión."
        case .cameraPermissionDenied:
            return "Autoriza la cámara en Configuración > Privacidad y seguridad > Cámara."
        case .microphonePermissionDenied:
            return "Autoriza el micrófono en Configuración > Privacidad y seguridad > Micrófono."
        case .cameraUnavailable:
            return "La cámara del iPad no está disponible."
        case .microphoneUnavailable:
            return "El micrófono del iPad no está disponible."
        case .photoPermissionDenied:
            return "Autoriza StudioPad para guardar la grabación en Fotos."
        }
    }
}
