import AVFoundation
import Combine
import HaishinKit
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

    private let mixer = MediaMixer()
    private var session: (any Session)?
    private var recorder: StreamRecorder?
    private weak var previewView: MTHKView?
    private var currentPosition: AVCaptureDevice.Position = .back
    private var isPrepared = false
    private var preparedURL: URL?

    var isLive: Bool { status == .live }
    var canStart: Bool { status == .idle }

    func attachPreview(_ view: MTHKView) {
        previewView = view
        Task { await mixer.addOutput(view) }
    }

    func prepare(using configuration: StreamConfiguration) async {
        guard !isPrepared else { return }
        status = .preparing

        do {
            try await requestCapturePermissions()
            try configureAudioSession()
            try await attachDevices()
            try await configureVideo(using: configuration)
            await configureCanvas()
            await mixer.startRunning()
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
                UIApplication.shared.isIdleTimerDisabled = true
                status = .live
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
            UIApplication.shared.isIdleTimerDisabled = false
            status = .idle
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
                try await mixer.attachVideo(device) { unit in
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
        Task {
            var settings = await mixer.audioMixerSettings
            var track = settings.tracks[0] ?? .init()
            track.isMuted = !isMuted
            settings.tracks[0] = track
            await mixer.setAudioMixerSettings(settings)
            isMuted.toggle()
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func shutdown() {
        Task {
            if isRecording {
                await finishRecordingAndSave()
            }
            if let session {
                try? await session.close()
                await mixer.removeOutput(session.stream)
            }
            session = nil
            preparedURL = nil
            await mixer.stopRunning()
            UIApplication.shared.isIdleTimerDisabled = false
            status = .idle
            isPrepared = false
        }
    }

    private func startRecording() {
        Task {
            do {
                let recorder = StreamRecorder()
                await mixer.addOutput(recorder)
                try await recorder.startRecording()
                self.recorder = recorder
                isRecording = true
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
            await mixer.removeOutput(recorder)
            self.recorder = nil
            isRecording = false

            guard let fileURL else { return }
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

        try await mixer.attachVideo(camera) { unit in
            unit.isVideoMirrored = false
        }
        try await mixer.attachAudio(microphone)
    }

    private func configureVideo(using configuration: StreamConfiguration) async throws {
        try await mixer.setFrameRate(Float64(configuration.framesPerSecond))
        await mixer.setVideoOrientation(.landscapeRight)

        var mixerSettings = await mixer.videoMixerSettings
        mixerSettings.mode = .offscreen
        await mixer.setVideoMixerSettings(mixerSettings)
    }

    @ScreenActor
    private func configureCanvas() async {
        await mixer.screen.size = CGSize(width: 1280, height: 720)
        await mixer.screen.backgroundColor = UIColor.black.cgColor
    }

    private func rebuildSession(url: URL, configuration: StreamConfiguration) async throws {
        if let session {
            await mixer.removeOutput(session.stream)
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
        await mixer.addOutput(newSession.stream)
    }

    private func applyEncodingSettings(_ configuration: StreamConfiguration) async throws {
        guard let session else { return }

        var videoSettings = await session.stream.videoSettings
        videoSettings.videoSize = CGSize(width: 1280, height: 720)
        videoSettings.bitRate = configuration.bitrate
        videoSettings.expectedFrameRate = Float64(configuration.framesPerSecond)
        videoSettings.profileLevel = kVTProfileLevel_H264_Main_AutoLevel as String
        try await session.stream.setVideoSettings(videoSettings)

        var audioSettings = await session.stream.audioSettings
        audioSettings.bitRate = 128_000
        try await session.stream.setAudioSettings(audioSettings)
    }

    private func friendlyMessage(for error: Error) -> String {
        if let studioError = error as? StudioError {
            return studioError.localizedDescription
        }
        return "No se pudo completar la operación: \(error.localizedDescription)"
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
