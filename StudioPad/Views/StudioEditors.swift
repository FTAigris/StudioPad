import PhotosUI
import SwiftUI

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

                if let importError {
                    Section {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Ajustes de fuente")
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
                importSelection(items)
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
                TextField("Color hexadecimal", text: $source.colorHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        case .image, .imageGallery, .media, .mediaGallery:
            Section(source.kind.title) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: selectionLimit,
                    matching: pickerFilter
                ) {
                    Label(
                        source.assetPaths.isEmpty ? "Elegir archivos" : "Cambiar archivos",
                        systemImage: "photo.badge.plus"
                    )
                }
                .disabled(isImporting)

                if isImporting {
                    HStack {
                        ProgressView()
                        Text("Importando…")
                    }
                } else {
                    Text("\(source.assetPaths.count) archivo(s) seleccionado(s)")
                        .foregroundStyle(.secondary)
                }

                if source.kind == .imageGallery || source.kind == .mediaGallery {
                    VStack(alignment: .leading) {
                        Text("Cambio cada \(Int(source.slideDuration)) segundos")
                        Slider(value: $source.slideDuration, in: 1 ... 30, step: 1)
                    }
                }

                if source.kind == .media || source.kind == .mediaGallery {
                    Toggle("Repetir reproducción", isOn: $source.loopsMedia)
                    Toggle("Silenciar multimedia", isOn: $source.isMediaMuted)
                    VStack(alignment: .leading) {
                        Text("Volumen \(Int(source.mediaVolume * 100)) %")
                        Slider(value: $source.mediaVolume, in: 0 ... 1)
                    }
                    .disabled(source.isMediaMuted)
                }
            }
        case .audioOutput:
            Section("Audio de salida") {
                Label("Se incluye al usar Capturar pantalla", systemImage: "rectangle.inset.filled.and.person.filled")
                Text("iPadOS no permite que una app capture libremente el sonido de otras apps. Esta fuente usa el audio que ReplayKit entrega cuando inicias Capturar pantalla.")
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

    private var selectionLimit: Int {
        switch source.kind {
        case .imageGallery, .mediaGallery: return 50
        default: return 1
        }
    }

    private var pickerFilter: PHPickerFilter {
        switch source.kind {
        case .image, .imageGallery: return .images
        default: return .videos
        }
    }

    private func importSelection(_ items: [PhotosPickerItem]) {
        isImporting = true
        importError = nil
        Task {
            do {
                let filenames = try await StudioMediaLibrary.importItems(items)
                await MainActor.run {
                    source.assetPaths = filenames
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
}
