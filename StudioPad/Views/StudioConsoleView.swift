import AVKit
import SwiftUI

struct StudioConsoleView: View {
    @EnvironmentObject private var configuration: StreamConfiguration
    @EnvironmentObject private var studio: StudioStore
    @StateObject private var outputs = ExternalDisplayManager.shared
    @State private var showsScreenControls = false
    @State private var showsSettings = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                consoleHeader
                Divider().overlay(Color.white.opacity(0.12))

                monitorSection(width: geometry.size.width)
                    .frame(height: max(300, geometry.size.height * 0.54))
                    .padding(10)

                Divider().overlay(Color.white.opacity(0.12))

                dockSection(width: geometry.size.width)
                    .frame(maxHeight: .infinity)

                statusBar
            }
            .background(Color(studioHex: "17191F"))
        }
        .preferredColorScheme(.dark)
        .task {
            await studio.cameraModel.prepare(using: configuration)
            studio.cameraModel.updateOutputConfiguration(using: configuration)
            studio.cameraModel.updateProgramScene(studio.programScene)
            studio.cameraModel.setExternalOutputActive(outputs.selectedDestination.isExternal)
            synchronizeMicrophoneControls()
        }
        .onChange(of: studio.programScene) { _, scene in
            studio.cameraModel.updateProgramScene(scene)
        }
        .onChange(of: configuration.outputWidth) { _, _ in
            studio.cameraModel.updateOutputConfiguration(using: configuration)
        }
        .onChange(of: configuration.outputHeight) { _, _ in
            studio.cameraModel.updateOutputConfiguration(using: configuration)
        }
        .onChange(of: configuration.framesPerSecond) { _, _ in
            studio.cameraModel.updateOutputConfiguration(using: configuration)
        }
        .onChange(of: outputs.selectedDestinationID) { _, _ in
            studio.cameraModel.setExternalOutputActive(outputs.selectedDestination.isExternal)
        }
        .sheet(isPresented: $showsScreenControls) {
            ScreenStudioView()
                .environmentObject(configuration)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .environmentObject(configuration)
        }
        .alert(
            "StudioPad",
            isPresented: Binding(
                get: { studio.cameraModel.errorMessage != nil },
                set: { if !$0 { studio.cameraModel.errorMessage = nil } }
            )
        ) {
            Button("Aceptar", role: .cancel) {
                studio.cameraModel.errorMessage = nil
            }
        } message: {
            Text(studio.cameraModel.errorMessage ?? "")
        }
    }

    private var consoleHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3.bold())
                .foregroundStyle(.red)
            Text("StudioPad")
                .font(.headline.bold())
            Text("MODO ESTUDIO")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())

            Spacer()

            Label(
                studio.cameraModel.status.label,
                systemImage: studio.cameraModel.isLive ? "circle.fill" : "circle"
            )
            .font(.caption.bold())
            .foregroundStyle(studio.cameraModel.isLive ? .red : .green)

            Button {
                showsScreenControls = true
            } label: {
                Label("Capturar pantalla", systemImage: "rectangle.inset.filled")
            }
            .consoleButtonStyle()

            Button {
                showsSettings = true
            } label: {
                Label("Ajustes", systemImage: "gearshape.fill")
            }
            .consoleButtonStyle()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(studioHex: "202229"))
    }

    @ViewBuilder
    private func monitorSection(width: CGFloat) -> some View {
        if width >= 900 {
            HStack(spacing: 10) {
                previewMonitor
                TransitionBridge(compact: false, performTransition: performTransition)
                    .frame(width: 142)
                programMonitor
            }
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    previewMonitor
                    TransitionBridge(compact: true, performTransition: performTransition)
                    programMonitor
                }
            }
        }
    }

    private var previewMonitor: some View {
        StudioMonitorPanel(
            title: "VISTA PREVIA",
            sceneName: studio.previewScene?.name ?? "Sin escena",
            accent: .green
        ) {
            EmptyView()
        } content: {
            StudioCanvas(
                scene: studio.previewScene,
                cameraModel: studio.cameraModel,
                canvasSize: configuration.outputSize
            )
        }
    }

    private var programMonitor: some View {
        StudioMonitorPanel(
            title: "PROGRAMA",
            sceneName: studio.programScene?.name ?? "Sin escena",
            accent: .red
        ) {
            outputMenu
        } content: {
            StudioCanvas(
                scene: studio.programScene,
                cameraModel: studio.cameraModel,
                canvasSize: configuration.outputSize
            )
                .id(studio.programSceneID)
        }
    }

    private var outputMenu: some View {
        Menu {
            ForEach(outputs.destinations) { destination in
                Button {
                    outputs.select(destination.id)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(destination.name)
                            Text(destination.detail)
                        }
                    } icon: {
                        Image(systemName: outputs.selectedDestinationID == destination.id
                              ? "checkmark.circle.fill"
                              : "display")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "display")
                Text(outputs.selectedDestination.name)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption.bold())
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seleccionar salida de Programa")
    }

    private func dockSection(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ScenesPanel()
                    .frame(width: 190)
                SourcesPanel()
                    .frame(width: 248)
                AudioMixerPanel()
                    .frame(width: 280)
                TransitionsPanel(performTransition: performTransition)
                    .frame(width: 205)
                ControlsPanel(
                    showsSettings: $showsSettings,
                    showsScreenControls: $showsScreenControls
                )
                .frame(width: 220)
            }
            .padding(8)
            .frame(minWidth: width, alignment: .leading)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label(
                outputs.selectedDestination.name,
                systemImage: outputs.selectedDestination.isExternal ? "display" : "ipad"
            )
            Spacer()
            if studio.cameraModel.isRecording {
                Label("GRABANDO", systemImage: "record.circle.fill")
                    .foregroundStyle(.orange)
            }
            if studio.cameraModel.isLive {
                Label("EN DIRECTO", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.red)
            }
            Text("\(Int(configuration.outputSize.width)) × \(Int(configuration.outputSize.height))")
            Text("\(configuration.framesPerSecond) FPS")
        }
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 25)
        .background(Color(studioHex: "202229"))
    }

    private func performTransition() {
        let animation: Animation? = studio.transition == .fade
            ? .easeInOut(duration: studio.transitionDuration)
            : nil
        withAnimation(animation) {
            studio.takeToProgram()
        }
    }

    private func synchronizeMicrophoneControls() {
        guard let microphone = studio.audioTracks.first(where: { $0.kind == .microphone }) else {
            return
        }
        studio.cameraModel.setMicrophoneVolume(Float(microphone.volume))
        studio.cameraModel.setMicrophoneMuted(microphone.isMuted)
    }
}

struct StudioCanvas: View {
    let scene: StudioScene?
    let cameraModel: CameraStudioModel
    let canvasSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if let scene {
                    ForEach(Array(scene.sources.reversed())) { source in
                        if source.isVisible {
                            sourceLayer(source, size: geometry.size)
                        }
                    }
                }

                if scene?.sources.contains(where: { $0.isVisible }) != true {
                    VStack(spacing: 10) {
                        Image(systemName: "rectangle.slash")
                            .font(.largeTitle)
                        Text("La escena no tiene fuentes visibles")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .background(.black)
        .aspectRatio(canvasSize.width / max(canvasSize.height, 1), contentMode: .fit)
    }

    @ViewBuilder
    private func sourceLayer(_ source: StudioSource, size: CGSize) -> some View {
        switch source.kind {
        case .camera:
            CameraPreview(model: cameraModel)
                .frame(width: size.width, height: size.height)
        case .screen:
            ZStack {
                LinearGradient(
                    colors: [Color(studioHex: "11141B"), Color(studioHex: "1C2330")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.system(size: min(size.width, size.height) * 0.15))
                    Text("Pantalla del iPad")
                        .font(.headline)
                    Text("Iníciala desde Capturar pantalla")
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        case .text:
            Text(source.text)
                .font(.system(size: max(20, min(size.width, size.height) * 0.09), weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.8), radius: 4, y: 2)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .color:
            Color(studioHex: source.colorHex)
        case .image, .imageGallery:
            StudioImageSourceLayer(source: source)
                .frame(width: size.width, height: size.height)
        case .media, .mediaGallery:
            StudioMediaSourceLayer(source: source)
                .frame(width: size.width, height: size.height)
        case .audioOutput:
            EmptyView()
        }
    }
}

private struct StudioImageSourceLayer: View {
    let source: StudioSource

    var body: some View {
        if source.kind == .imageGallery, source.assetPaths.count > 1 {
            TimelineView(.periodic(from: .now, by: max(source.slideDuration, 1))) { context in
                image(for: galleryIndex(at: context.date))
            }
        } else {
            image(for: 0)
        }
    }

    @ViewBuilder
    private func image(for index: Int) -> some View {
        if source.assetPaths.indices.contains(index),
           let url = StudioMediaLibrary.url(for: source.assetPaths[index]),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            sourcePlaceholder(icon: source.kind.icon, title: "Elige imágenes en Ajustes de fuente")
        }
    }

    private func galleryIndex(at date: Date) -> Int {
        guard !source.assetPaths.isEmpty else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / max(source.slideDuration, 1)) % source.assetPaths.count
    }
}

private struct StudioMediaSourceLayer: View {
    let source: StudioSource

    var body: some View {
        if source.kind == .mediaGallery, source.assetPaths.count > 1 {
            TimelineView(.periodic(from: .now, by: max(source.slideDuration, 1))) { context in
                player(for: galleryIndex(at: context.date))
            }
        } else {
            player(for: 0)
        }
    }

    @ViewBuilder
    private func player(for index: Int) -> some View {
        if source.assetPaths.indices.contains(index),
           let url = StudioMediaLibrary.url(for: source.assetPaths[index]) {
            StudioVideoPlayer(
                url: url,
                loops: source.loopsMedia,
                isMuted: source.isMediaMuted,
                volume: Float(source.mediaVolume)
            )
        } else {
            sourcePlaceholder(icon: source.kind.icon, title: "Elige videos en Ajustes de fuente")
        }
    }

    private func galleryIndex(at date: Date) -> Int {
        guard !source.assetPaths.isEmpty else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / max(source.slideDuration, 1)) % source.assetPaths.count
    }
}

private struct StudioVideoPlayer: View {
    let url: URL
    let loops: Bool
    let isMuted: Bool
    let volume: Float

    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .task(id: url) {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                player.isMuted = isMuted
                player.volume = volume
                player.play()
            }
            .onChange(of: isMuted) { _, muted in player.isMuted = muted }
            .onChange(of: volume) { _, newVolume in player.volume = newVolume }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
                guard loops,
                      let endedItem = notification.object as? AVPlayerItem,
                      endedItem === player.currentItem else { return }
                player.seek(to: .zero)
                player.play()
            }
            .onDisappear { player.pause() }
    }
}

@ViewBuilder
private func sourcePlaceholder(icon: String, title: String) -> some View {
    ZStack {
        Color.black.opacity(0.72)
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

struct ExternalProgramView: View {
    let sessionID: String
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var outputs: ExternalDisplayManager
    @EnvironmentObject private var configuration: StreamConfiguration

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if outputs.selectedDestinationID == sessionID {
                StudioCanvas(
                    scene: studio.programScene,
                    cameraModel: studio.cameraModel,
                    canvasSize: configuration.outputSize
                )
                    .id(studio.programSceneID)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "display")
                        .font(.system(size: 72, weight: .light))
                    Text("Salida en espera")
                        .font(.largeTitle.bold())
                    Text("Selecciona esta pantalla en el menú de Programa del iPad.")
                        .font(.title3)
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct StudioMonitorPanel<Accessory: View, Content: View>: View {
    let title: String
    let sceneName: String
    let accent: Color
    let accessory: Accessory
    let content: Content

    init(
        title: String,
        sceneName: String,
        accent: Color,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sceneName = sceneName
        self.accent = accent
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(accent)
                Text(sceneName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer(minLength: 6)
                accessory
            }
            .padding(.horizontal, 10)
            .frame(height: 40)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .overlay {
                    Rectangle().stroke(accent.opacity(0.75), lineWidth: 2)
                }
                .padding([.horizontal, .bottom], 8)
        }
        .background(Color(studioHex: "202229"), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct TransitionBridge: View {
    @EnvironmentObject private var studio: StudioStore
    let compact: Bool
    let performTransition: () -> Void

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    transitionButton
                    transitionPicker
                    durationLabel
                }
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                    transitionButton
                    transitionPicker
                    durationLabel
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(Color(studioHex: "202229"), in: RoundedRectangle(cornerRadius: 8))
    }

    private var transitionButton: some View {
        Button(action: performTransition) {
            Label("Transición", systemImage: "arrow.right.square.fill")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private var transitionPicker: some View {
        Picker("Transición", selection: $studio.transition) {
            ForEach(StudioTransitionKind.allCases) { transition in
                Label(transition.title, systemImage: transition.icon)
                    .tag(transition)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(.white)
    }

    private var durationLabel: some View {
        Text(studio.transition == .cut ? "Instantánea" : "\(Int(studio.transitionDuration * 1_000)) ms")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

private struct ScenesPanel: View {
    @EnvironmentObject private var studio: StudioStore
    @State private var editingScene: StudioScene?

    var body: some View {
        DockPanel(title: "Escenas", icon: "square.stack.3d.up.fill") {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(studio.scenes) { scene in
                        Button {
                            studio.selectPreviewScene(scene.id)
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(scene.id == studio.programSceneID ? Color.red : Color.clear)
                                    .frame(width: 7, height: 7)
                                Text(scene.name)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if scene.id == studio.previewSceneID {
                                    Image(systemName: "eye.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .background(
                                scene.id == studio.previewSceneID
                                    ? Color.blue.opacity(0.7)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingScene = scene
                            } label: {
                                Label("Renombrar", systemImage: "pencil")
                            }
                        }
                        .draggable(scene.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let rawID = items.first,
                                  let sourceID = UUID(uuidString: rawID) else { return false }
                            studio.moveScene(sourceID, to: scene.id)
                            return true
                        }
                    }
                }
                .padding(6)
            }
        } footer: {
            HStack(spacing: 4) {
                SmallIconButton(icon: "plus", label: "Añadir escena", action: studio.addScene)
                SmallIconButton(icon: "trash", label: "Eliminar escena", action: studio.deletePreviewScene)
                SmallIconButton(icon: "pencil", label: "Renombrar escena") {
                    editingScene = studio.previewScene
                }
                Spacer()
            }
        }
        .sheet(item: $editingScene) { scene in
            SceneRenameView(sceneID: scene.id, currentName: scene.name) { id, name in
                studio.renameScene(id, to: name)
            }
        }
    }
}

private struct SourcesPanel: View {
    @EnvironmentObject private var studio: StudioStore
    @State private var settingsSource: StudioSource?

    var body: some View {
        DockPanel(title: "Fuentes", icon: "photo.on.rectangle.angled") {
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(studio.previewScene?.sources ?? []) { source in
                        HStack(spacing: 5) {
                            Button {
                                studio.selectedSourceID = source.id
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: source.kind.icon)
                                        .frame(width: 18)
                                    Text(source.name)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "line.3.horizontal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                studio.toggleSourceVisibility(source.id)
                            } label: {
                                Image(systemName: source.isVisible ? "eye.fill" : "eye.slash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(source.isVisible ? .white : .secondary)
                            .accessibilityLabel(source.isVisible ? "Ocultar fuente" : "Mostrar fuente")

                            Button {
                                studio.toggleSourceLock(source.id)
                            } label: {
                                Image(systemName: source.isLocked ? "lock.fill" : "lock.open")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(source.isLocked ? .orange : .secondary)
                            .accessibilityLabel(source.isLocked ? "Desbloquear fuente" : "Bloquear fuente")
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 32)
                        .background(
                            studio.selectedSourceID == source.id
                                ? Color.blue.opacity(0.7)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contextMenu {
                            Button {
                                studio.selectedSourceID = source.id
                                settingsSource = source
                            } label: {
                                Label("Ajustes y nombre", systemImage: "gearshape")
                            }
                        }
                        .draggable(source.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let rawID = items.first,
                                  let sourceID = UUID(uuidString: rawID) else { return false }
                            studio.moveSource(sourceID, to: source.id)
                            return true
                        }
                    }
                }
                .padding(6)
            }
        } footer: {
            HStack(spacing: 4) {
                Menu {
                    ForEach(StudioSourceKind.allCases) { kind in
                        Button {
                            studio.addSource(kind)
                        } label: {
                            Label(kind.title, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir fuente")

                SmallIconButton(icon: "trash", label: "Eliminar fuente", action: studio.deleteSelectedSource)
                SmallIconButton(icon: "gearshape", label: "Ajustes de fuente") {
                    settingsSource = studio.selectedSource
                }
                Spacer()
                SmallIconButton(icon: "chevron.up", label: "Subir fuente") {
                    studio.moveSelectedSource(by: -1)
                }
                SmallIconButton(icon: "chevron.down", label: "Bajar fuente") {
                    studio.moveSelectedSource(by: 1)
                }
            }
        }
        .sheet(item: $settingsSource) { source in
            SourceSettingsView(source: source, onSave: studio.updateSource)
        }
    }
}

private struct AudioMixerPanel: View {
    @EnvironmentObject private var studio: StudioStore

    var body: some View {
        DockPanel(title: "Mezclador de audio", icon: "slider.vertical.3") {
            VStack(spacing: 8) {
                ForEach(studio.audioTracks) { track in
                    VStack(spacing: 5) {
                        HStack {
                            Text(track.name)
                                .font(.caption.bold())
                            Spacer()
                            Text("\(Int(track.volume * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 7) {
                            AudioLevelBar(level: track.isMuted ? 0 : track.volume)

                            Slider(
                                value: Binding(
                                    get: { track.volume },
                                    set: { studio.setAudioVolume($0, for: track.id) }
                                ),
                                in: 0 ... 1
                            )
                            .tint(.blue)

                            Button {
                                studio.toggleAudioMute(track.id)
                            } label: {
                                Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(track.isMuted ? .red : .white)
                        }
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer(minLength: 0)
            }
            .padding(7)
        } footer: {
            HStack {
                Label("2 pistas", systemImage: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

private struct AudioLevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.7))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        .frame(width: 58, height: 7)
        .accessibilityLabel("Nivel \(Int(level * 100)) por ciento")
    }
}

private struct TransitionsPanel: View {
    @EnvironmentObject private var studio: StudioStore
    let performTransition: () -> Void

    var body: some View {
        DockPanel(title: "Transiciones", icon: "arrow.left.arrow.right") {
            VStack(spacing: 10) {
                Picker("Tipo", selection: $studio.transition) {
                    ForEach(StudioTransitionKind.allCases) { transition in
                        Label(transition.title, systemImage: transition.icon)
                            .tag(transition)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Duración")
                        Spacer()
                        Text("\(Int(studio.transitionDuration * 1_000)) ms")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    Slider(value: $studio.transitionDuration, in: 0.1 ... 2, step: 0.1)
                        .disabled(studio.transition == .cut)
                }

                Button(action: performTransition) {
                    Label("Aplicar transición", systemImage: "arrow.right.square.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                HStack(spacing: 6) {
                    Button("Corte") {
                        studio.transition = .cut
                        performTransition()
                    }
                    Button("Fundido") {
                        studio.transition = .fade
                        performTransition()
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            .padding(8)
        } footer: {
            EmptyView()
        }
    }
}

private struct ControlsPanel: View {
    @EnvironmentObject private var studio: StudioStore
    @EnvironmentObject private var configuration: StreamConfiguration
    @Binding var showsSettings: Bool
    @Binding var showsScreenControls: Bool

    var body: some View {
        DockPanel(title: "Controles", icon: "switch.2") {
            VStack(spacing: 7) {
                Button(action: toggleLive) {
                    Label(
                        studio.cameraModel.isLive ? "Finalizar transmisión" : "Iniciar transmisión",
                        systemImage: studio.cameraModel.isLive ? "stop.fill" : "dot.radiowaves.left.and.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(studio.cameraModel.isLive ? .gray : .red)
                .disabled(
                    studio.cameraModel.status == .preparing
                        || studio.cameraModel.status == .connecting
                        || studio.cameraModel.status == .stopping
                )

                Button(action: studio.cameraModel.toggleRecording) {
                    Label(
                        studio.cameraModel.isRecording ? "Detener grabación" : "Iniciar grabación",
                        systemImage: studio.cameraModel.isRecording ? "stop.circle.fill" : "record.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(studio.cameraModel.isRecording ? .orange : .white)

                Button(action: studio.cameraModel.flipCamera) {
                    Label(studio.cameraModel.cameraLabel, systemImage: "arrow.triangle.2.circlepath.camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                HStack(spacing: 7) {
                    Button {
                        showsScreenControls = true
                    } label: {
                        Label("Pantalla", systemImage: "rectangle.inset.filled")
                    }
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Ajustes", systemImage: "gearshape")
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)

                if !configuration.isValid {
                    Label("Configura el destino RTMP", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
        } footer: {
            EmptyView()
        }
    }

    private func toggleLive() {
        if studio.cameraModel.isLive {
            studio.cameraModel.stopStreaming()
        } else if configuration.isValid {
            studio.cameraModel.startStreaming(using: configuration)
        } else {
            showsSettings = true
        }
    }
}

private struct DockPanel<Content: View, Footer: View>: View {
    let title: String
    let icon: String
    let content: Content
    let footer: Footer

    init(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color.white.opacity(0.045))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
                .padding(.horizontal, 7)
                .frame(height: 34)
                .background(Color.black.opacity(0.18))
        }
        .background(Color(studioHex: "202229"))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }
}

private struct SmallIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 26)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private extension View {
    func consoleButtonStyle() -> some View {
        self
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

private extension Color {
    init(studioHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
            .scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
