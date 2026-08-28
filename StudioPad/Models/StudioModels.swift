import Combine
import Foundation

enum StudioSourceKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case camera
    case screen
    case text
    case color

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Cámara"
        case .screen: return "Pantalla del iPad"
        case .text: return "Texto"
        case .color: return "Fondo de color"
        }
    }

    var icon: String {
        switch self {
        case .camera: return "video.fill"
        case .screen: return "rectangle.inset.filled"
        case .text: return "textformat"
        case .color: return "paintpalette.fill"
        }
    }
}

struct StudioSource: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var kind: StudioSourceKind
    var isVisible: Bool
    var isLocked: Bool
    var text: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        kind: StudioSourceKind,
        isVisible: Bool = true,
        isLocked: Bool = false,
        text: String = "StudioPad",
        colorHex: String = "1A1D24"
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.text = text
        self.colorHex = colorHex
    }
}

struct StudioScene: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var sources: [StudioSource]

    init(id: UUID = UUID(), name: String, sources: [StudioSource]) {
        self.id = id
        self.name = name
        self.sources = sources
    }
}

enum StudioAudioTrackKind: String, Codable, Sendable {
    case microphone
    case screen
}

struct StudioAudioTrack: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var kind: StudioAudioTrackKind
    var volume: Double
    var isMuted: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: StudioAudioTrackKind,
        volume: Double = 0.8,
        isMuted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.volume = volume
        self.isMuted = isMuted
    }
}

enum StudioTransitionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cut
    case fade

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cut: return "Corte"
        case .fade: return "Desvanecer"
        }
    }

    var icon: String {
        switch self {
        case .cut: return "scissors"
        case .fade: return "circle.lefthalf.filled"
        }
    }
}

@MainActor
final class StudioStore: ObservableObject {
    static let shared = StudioStore()

    @Published private(set) var scenes: [StudioScene]
    @Published var previewSceneID: UUID
    @Published private(set) var programSceneID: UUID
    @Published var selectedSourceID: UUID?
    @Published var transition: StudioTransitionKind
    @Published var transitionDuration: Double
    @Published private(set) var audioTracks: [StudioAudioTrack]

    let cameraModel = CameraStudioModel()

    private enum Keys {
        static let document = "studio.document.v1"
    }

    private struct Document: Codable {
        var scenes: [StudioScene]
        var previewSceneID: UUID
        var programSceneID: UUID
        var transition: StudioTransitionKind
        var transitionDuration: Double
        var audioTracks: [StudioAudioTrack]
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.document),
           let document = try? JSONDecoder().decode(Document.self, from: data),
           !document.scenes.isEmpty,
           document.scenes.contains(where: { $0.id == document.previewSceneID }),
           document.scenes.contains(where: { $0.id == document.programSceneID }) {
            scenes = document.scenes
            previewSceneID = document.previewSceneID
            programSceneID = document.programSceneID
            transition = document.transition
            transitionDuration = document.transitionDuration
            audioTracks = document.audioTracks
            selectedSourceID = document.scenes
                .first(where: { $0.id == document.previewSceneID })?
                .sources.first?.id
            return
        }

        let cameraScene = StudioScene(
            name: "Cámara",
            sources: [StudioSource(name: "Cámara principal", kind: .camera)]
        )
        let screenScene = StudioScene(
            name: "Pantalla",
            sources: [StudioSource(name: "Pantalla del iPad", kind: .screen)]
        )
        let pauseScene = StudioScene(
            name: "Pausa",
            sources: [
                StudioSource(
                    name: "Texto de pausa",
                    kind: .text,
                    text: "Volvemos enseguida"
                ),
                StudioSource(
                    name: "Fondo oscuro",
                    kind: .color,
                    colorHex: "111318"
                ),
            ]
        )

        scenes = [cameraScene, screenScene, pauseScene]
        previewSceneID = cameraScene.id
        programSceneID = cameraScene.id
        selectedSourceID = cameraScene.sources.first?.id
        transition = .fade
        transitionDuration = 0.3
        audioTracks = [
            StudioAudioTrack(name: "Micrófono", kind: .microphone),
            StudioAudioTrack(name: "Audio del iPad", kind: .screen),
        ]
    }

    var previewScene: StudioScene? {
        scenes.first(where: { $0.id == previewSceneID })
    }

    var programScene: StudioScene? {
        scenes.first(where: { $0.id == programSceneID })
    }

    func selectPreviewScene(_ id: UUID) {
        guard let scene = scenes.first(where: { $0.id == id }) else { return }
        previewSceneID = scene.id
        selectedSourceID = scene.sources.first?.id
        save()
    }

    func takeToProgram() {
        guard scenes.contains(where: { $0.id == previewSceneID }) else { return }
        programSceneID = previewSceneID
        save()
    }

    func setQuickTransition(_ kind: StudioTransitionKind) {
        transition = kind
        takeToProgram()
    }

    func addScene() {
        let number = scenes.count + 1
        let source = StudioSource(name: "Cámara principal", kind: .camera)
        let scene = StudioScene(name: "Escena \(number)", sources: [source])
        scenes.append(scene)
        previewSceneID = scene.id
        selectedSourceID = source.id
        save()
    }

    func deletePreviewScene() {
        guard scenes.count > 1,
              let index = scenes.firstIndex(where: { $0.id == previewSceneID }) else { return }

        let removedID = scenes[index].id
        scenes.remove(at: index)
        let replacement = scenes[min(index, scenes.count - 1)]
        previewSceneID = replacement.id
        selectedSourceID = replacement.sources.first?.id
        if programSceneID == removedID {
            programSceneID = replacement.id
        }
        save()
    }

    func addSource(_ kind: StudioSourceKind) {
        guard let sceneIndex = previewSceneIndex else { return }
        let repeated = scenes[sceneIndex].sources.filter { $0.kind == kind }.count
        let suffix = repeated == 0 ? "" : " \(repeated + 1)"
        let source = StudioSource(
            name: kind.title + suffix,
            kind: kind,
            text: kind == .text ? "Nuevo texto" : "StudioPad",
            colorHex: kind == .color ? "173A5E" : "1A1D24"
        )
        scenes[sceneIndex].sources.insert(source, at: 0)
        selectedSourceID = source.id
        save()
    }

    func deleteSelectedSource() {
        guard let sceneIndex = previewSceneIndex,
              let selectedSourceID,
              let sourceIndex = scenes[sceneIndex].sources.firstIndex(where: { $0.id == selectedSourceID }),
              !scenes[sceneIndex].sources[sourceIndex].isLocked else { return }

        scenes[sceneIndex].sources.remove(at: sourceIndex)
        self.selectedSourceID = scenes[sceneIndex].sources.first?.id
        save()
    }

    func toggleSourceVisibility(_ id: UUID) {
        guard let location = sourceLocation(id) else { return }
        scenes[location.scene].sources[location.source].isVisible.toggle()
        save()
    }

    func toggleSourceLock(_ id: UUID) {
        guard let location = sourceLocation(id) else { return }
        scenes[location.scene].sources[location.source].isLocked.toggle()
        save()
    }

    func moveSelectedSource(by offset: Int) {
        guard let sceneIndex = previewSceneIndex,
              let selectedSourceID,
              let sourceIndex = scenes[sceneIndex].sources.firstIndex(where: { $0.id == selectedSourceID }) else {
            return
        }

        let destination = sourceIndex + offset
        guard scenes[sceneIndex].sources.indices.contains(destination) else { return }
        scenes[sceneIndex].sources.swapAt(sourceIndex, destination)
        save()
    }

    func setAudioVolume(_ volume: Double, for trackID: UUID) {
        guard let index = audioTracks.firstIndex(where: { $0.id == trackID }) else { return }
        audioTracks[index].volume = min(max(volume, 0), 1)
        if audioTracks[index].kind == .microphone {
            cameraModel.setMicrophoneVolume(Float(audioTracks[index].volume))
        }
        save()
    }

    func toggleAudioMute(_ trackID: UUID) {
        guard let index = audioTracks.firstIndex(where: { $0.id == trackID }) else { return }
        audioTracks[index].isMuted.toggle()
        if audioTracks[index].kind == .microphone {
            cameraModel.setMicrophoneMuted(audioTracks[index].isMuted)
        }
        save()
    }

    private var previewSceneIndex: Int? {
        scenes.firstIndex(where: { $0.id == previewSceneID })
    }

    private func sourceLocation(_ id: UUID) -> (scene: Int, source: Int)? {
        guard let sceneIndex = previewSceneIndex,
              let sourceIndex = scenes[sceneIndex].sources.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return (sceneIndex, sourceIndex)
    }

    private func save() {
        let document = Document(
            scenes: scenes,
            previewSceneID: previewSceneID,
            programSceneID: programSceneID,
            transition: transition,
            transitionDuration: transitionDuration,
            audioTracks: audioTracks
        )
        if let data = try? JSONEncoder().encode(document) {
            defaults.set(data, forKey: Keys.document)
        }
    }
}
