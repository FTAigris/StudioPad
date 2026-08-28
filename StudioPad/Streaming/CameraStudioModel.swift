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
    private let programMixer = MediaMixer(captureSessionMode: .manual)
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

        let sources = scene?.sources.filter(\.isVisible) ?? []
        if !sources.contains(where: { $0.kind == .camera }),
           let black = makeSolidImage(hex: "000000", size: size) {
            await addProgramImage(black, size: size)
        }

        for source in sources.reversed() {
            switch source.kind {
            case .camera, .audioOutput:
                continue
            case .color:
                if let image = makeSolidImage(hex: source.colorHex, size: size) {
                    await addProgramImage(image, size: size)
                }
            case .screen:
                if let image = makeSolidImage(hex: "11141B", size: size) {
                    await addProgramImage(image, size: size)
                }
                await addProgramText("Pantalla del iPad\nIníciala desde Capturar pantalla", size: size)
            case .text:
                await addProgramText(source.text, size: size)
            case .image:
                guard let filename = source.assetPaths.first,
                      let url = StudioMediaLibrary.url(for: filename),
                      let image = makeCanvasImage(from: url, size: size) else { continue }
                await addProgramImage(image, size: size)
            case .imageGallery:
                let filenames = source.assetPaths.filter { StudioMediaLibrary.url(for: $0) != nil }
                guard let filename = filenames.first,
                      let url = StudioMediaLibrary.url(for: filename),
                      let image = makeCanvasImage(from: url, size: size) else { continue }
                let object = ImageScreenObject()
                object.cgImage = image
                object.size = size
                try? await programMixer.screen.addChild(object)
                activeProgramObjects.append(object)
                imageGalleryStates.append(
                    ProgramImageGalleryState(
                        object: object,
                        filenames: filenames,
                        index: 0,
                        interval: max(source.slideDuration, 1),
                        nextChange: Date.timeIntervalSinceReferenceDate + max(source.slideDuration, 1),
                        canvasSize: size
                    )
                )
            case .media, .mediaGallery:
                let urls = source.assetPaths.compactMap(StudioMediaLibrary.url(for:))
                guard let url = urls.first else { continue }
                let object = AssetScreenObject()
                object.size = size
                object.videoGravity = .resizeAspect
                try? object.startReading(AVURLAsset(url: url))
                try? await programMixer.screen.addChild(object)
                activeProgramObjects.append(object)
                if source.loopsMedia || urls.count > 1 {
                    mediaStates.append(
                        ProgramMediaState(
                            object: object,
                            urls: urls,
                            index: 0,
                            interval: max(source.slideDuration, 1),
                            nextChange: Date.timeIntervalSinceReferenceDate + max(source.slideDuration, 1),
                            loops: source.loopsMedia,
                            isGallery: source.kind == .mediaGallery
                        )
                    )
                }
            }
        }

        startProgramAnimationLoopIfNeeded()
    }

    @ScreenActor
    private func clearProgramObjects() async {
        programAnimationTask?.cancel()
        programAnimationTask = nil
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

                for index in imageGalleryStates.indices where now >= imageGalleryStates[index].nextChange {
                    imageGalleryStates[index].index =
                        (imageGalleryStates[index].index + 1) % imageGalleryStates[index].filenames.count
                    let filename = imageGalleryStates[index].filenames[imageGalleryStates[index].index]
                    if let url = StudioMediaLibrary.url(for: filename),
                       let image = makeCanvasImage(from: url, size: imageGalleryStates[index].canvasSize) {
                        imageGalleryStates[index].object.cgImage = image
                        imageGalleryStates[index].object.invalidateLayout()
                    }
                    imageGalleryStates[index].nextChange = now + imageGalleryStates[index].interval
                }

                for index in mediaStates.indices {
                    let state = mediaStates[index]
                    if state.isGallery, now >= state.nextChange {
                        let isLast = state.index == state.urls.count - 1
                        if !isLast || state.loops {
                            mediaStates[index].index = (state.index + 1) % state.urls.count
                            mediaStates[index].object.cancelReading()
                            try? mediaStates[index].object.startReading(
                                AVURLAsset(url: mediaStates[index].urls[mediaStates[index].index])
                            )
                        }
                        mediaStates[index].nextChange = now + state.interval
                    } else if !state.isGallery, state.loops, !state.object.isReading {
                        try? mediaStates[index].object.startReading(AVURLAsset(url: state.urls[state.index]))
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
    private func addProgramText(_ text: String, size: CGSize) async {
        let object = TextScreenObject()
        object.string = text
        object.attributes = [
            .font: UIFont.boldSystemFont(ofSize: max(32, size.height * 0.07)),
            .foregroundColor: UIColor.white,
        ]
        object.horizontalAlignment = .center
        object.verticalAlignment = .middle
        object.size = CGSize(width: size.width * 0.9, height: size.height * 0.8)
        object.invalidateLayout()
        try? await programMixer.screen.addChild(object)
        activeProgramObjects.append(object)
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
}

private struct ProgramMediaState {
    let object: AssetScreenObject
    let urls: [URL]
    var index: Int
    let interval: TimeInterval
    var nextChange: TimeInterval
    let loops: Bool
    let isGallery: Bool
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
