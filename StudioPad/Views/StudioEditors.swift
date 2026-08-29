import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SceneRenameView: View {
    let sceneID: UUID
    let currentName: String
    let onSave: (UUID, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(sceneID: UUID, currentName: String, onSave: @escaping (UUID, String) -> Void) {
        self.sceneID = sceneID
        self.currentName = currentName
        self.onSave = onSave
        _name = State(initialValue: currentName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre de la escena", text: $name)
                    .textInputAutocapitalization(.sentences)
            }
            .navigationTitle("Renombrar escena")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(sceneID, name)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct SourceSettingsView: View {
    let onSave: (StudioSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: StudioSource
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var isImporting = false
    @State private var importError: String?

    init(source: StudioSource, onSave: @escaping (StudioSource) -> Void) {
        self.onSave = onSave
        _source = State(initialValue: source)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuente") {
                    Label(source.kind.title, systemImage: source.kind.icon)
                    TextField("Nombre", text: $source.name)
                    Toggle("Visible", isOn: $source.isVisible)
                    Toggle("Bloqueada", isOn: $source.isLocked)
                }

                sourceControls

                if source.kind.hasVisualContent {
                    SourceGeometryEditor(source: $source)
                }

                if let importError {
                    Section {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Propiedades de \(source.kind.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(source)
                        dismiss()
                    }
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                importPhotoSelection(items)
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: selectionLimit > 1
            ) { result in
                importFileSelection(result)
            }
        }
    }

    @ViewBuilder
    private var sourceControls: some View {
        switch source.kind {
        case .text:
            Section("Texto") {
                TextEditor(text: $source.text)
                    .frame(minHeight: 100)
            }

        case .color:
            Section("Color") {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(studioSourceHex: source.colorHex))
                    .frame(height: 150)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                TextField("Código hexadecimal", text: $source.colorHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                ColorPicker(
                    "Seleccionar en la paleta",
                    selection: colorBinding,
                    supportsOpacity: false
                )
            }

        case .image:
            mediaSelectionSection(includePhotos: true)

        case .imageGallery:
            mediaSelectionSection(includePhotos: true)
            Section("Presentación") {
                Stepper(
                    "Tiempo entre diapositivas: \(source.slideDuration, specifier: "%.1f") s",
                    value: $source.slideDuration,
                    in: 1 ... 60,
                    step: 0.5
                )
                Stepper(
                    "Velocidad de transición: \(source.galleryTransitionDuration, specifier: "%.1f") s",
                    value: $source.galleryTransitionDuration,
                    in: 0 ... 5,
                    step: 0.1
                )
                Picker("Modo de reproducción", selection: $source.galleryPlaybackMode) {
                    ForEach(StudioGalleryPlaybackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

        case .media:
            mediaSelectionSection(includePhotos: true)
            Section("Reproducción") {
                Toggle("Bucle", isOn: $source.loopsMedia)
                Toggle("Reiniciar cuando la fuente esté activa", isOn: $source.restartWhenActive)
                Toggle("Ocultar al terminar la reproducción", isOn: $source.hideWhenFinished)
                playbackSpeedControl
            }

        case .mediaGallery:
            mediaSelectionSection(includePhotos: true)
            Section("Lista de reproducción") {
                Toggle("Repetir lista de reproducción", isOn: $source.loopsMedia)
                Toggle("Mezclar lista de reproducción", isOn: $source.shufflesPlaylist)
                Picker("Comportamiento de visibilidad", selection: $source.visibilityBehavior) {
                    ForEach(StudioVisibilityBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                playbackSpeedControl
                Text("El siguiente video comenzará cuando termine el video actual.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .audioOutput:
            mediaSelectionSection(includePhotos: false)
            Section("Captura de audio") {
                Toggle("Bucle", isOn: $source.loopsMedia)
                Toggle("Reiniciar cuando la fuente esté activa", isOn: $source.restartWhenActive)
                Text("Puedes elegir un archivo de audio o un video. Si eliges un video, StudioPad utilizará solamente su sonido.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .audioPlaylist:
            mediaSelectionSection(includePhotos: false)
            Section("Lista de audio") {
                Toggle("Repetir lista de reproducción", isOn: $source.loopsMedia)
                Toggle("Mezclar lista de reproducción", isOn: $source.shufflesPlaylist)
                Picker("Comportamiento de visibilidad", selection: $source.visibilityBehavior) {
                    ForEach(StudioVisibilityBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                Text("Cada elemento se reproduce completo antes de pasar al siguiente.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .screen:
            Section("Pantalla del iPad") {
                Text("Inicia la captura desde el botón Pantalla de la consola.")
                    .foregroundStyle(.secondary)
            }

        case .camera:
            Section("Cámara") {
                Text("La cámara activa se cambia desde Controles.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func mediaSelectionSection(includePhotos: Bool) -> some View {
        Section("Archivos") {
            HStack(spacing: 12) {
                if includePhotos {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: selectionLimit,
                        matching: pickerFilter
                    ) {
                        Label("Fotos", systemImage: "photo.badge.plus")
                    }
                    .disabled(isImporting)
                }

                Button {
                    showsFileImporter = true
                } label: {
                    Label("Archivos", systemImage: "folder.badge.plus")
                }
                .disabled(isImporting)
            }

            if isImporting {
                HStack {
                    ProgressView()
                    Text("Importando…")
                }
            }

            if source.assetPaths.isEmpty {
                Text("No hay archivos seleccionados")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(source.assetPaths.enumerated()), id: \.element) { index, path in
                    HStack(spacing: 8) {
                        Text("\(index + 1). \(StudioMediaLibrary.displayName(for: path))")
                            .lineLimit(1)
                        Spacer()
                        Button {
                            moveAsset(at: index, by: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)

                        Button {
                            moveAsset(at: index, by: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == source.assetPaths.count - 1)

                        Button(role: .destructive) {
                            source.assetPaths.remove(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var playbackSpeedControl: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Velocidad: \(source.playbackRate, specifier: "%.2f")×")
            Slider(value: $source.playbackRate, in: 0.25 ... 2, step: 0.05)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(studioSourceHex: source.colorHex) },
            set: { source.colorHex = UIColor($0).studioHexString }
        )
    }

    private var selectionLimit: Int {
        switch source.kind {
        case .imageGallery, .mediaGallery, .audioPlaylist: return 50
        default: return 1
        }
    }

    private var pickerFilter: PHPickerFilter {
        switch source.kind {
        case .image, .imageGallery: return .images
        default: return .videos
        }
    }

    private var allowedContentTypes: [UTType] {
        switch source.kind {
        case .image, .imageGallery:
            return [.image]
        case .media, .mediaGallery:
            return [.movie, .video]
        case .audioOutput, .audioPlaylist:
            return [.audio, .movie, .video]
        default:
            return [.data]
        }
    }

    private func importPhotoSelection(_ items: [PhotosPickerItem]) {
        isImporting = true
        importError = nil
        Task {
            do {
                let filenames = try await StudioMediaLibrary.importItems(items)
                await MainActor.run {
                    applyImportedFiles(filenames)
                    pickerItems = []
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = "No se pudieron importar los archivos: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }

    private func importFileSelection(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let filenames = try StudioMediaLibrary.importFiles(urls)
            applyImportedFiles(filenames)
        } catch {
            importError = "No se pudieron importar los archivos: \(error.localizedDescription)"
        }
    }

    private func applyImportedFiles(_ filenames: [String]) {
        if selectionLimit == 1 {
            source.assetPaths = Array(filenames.prefix(1))
        } else {
            source.assetPaths.append(contentsOf: filenames)
        }
    }

    private func moveAsset(at index: Int, by offset: Int) {
        let destination = index + offset
        guard source.assetPaths.indices.contains(index),
              source.assetPaths.indices.contains(destination) else { return }
        source.assetPaths.swapAt(index, destination)
    }
}

private struct SourceGeometryEditor: View {
    @Binding var source: StudioSource

    var body: some View {
        Section("Posición y tamaño en píxeles") {
            HStack {
                pixelField("X", value: $source.canvasX, signed: true)
                pixelField("Y", value: $source.canvasY, signed: true)
            }
            HStack {
                pixelField("Ancho", value: $source.canvasWidth, signed: false)
                pixelField("Alto", value: $source.canvasHeight, signed: false)
            }
            Text("X e Y indican la esquina superior izquierda dentro del lienzo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func pixelField(_ title: String, value: Binding<Double>, signed: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
            TextField(
                title,
                value: value,
                format: .number.precision(.fractionLength(0))
            )
            .keyboardType(signed ? .numbersAndPunctuation : .numberPad)
            .multilineTextAlignment(.trailing)
            Text("px")
                .foregroundStyle(.secondary)
        }
    }
}

private extension Color {
    init(studioSourceHex hex: String) {
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

private extension UIColor {
    var studioHexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            let component = Int(white * 255)
            return String(format: "%02X%02X%02X", component, component, component)
        }
        return "000000"
    }
}
