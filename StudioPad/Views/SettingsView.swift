import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var configuration: StreamConfiguration

    var body: some View {
        NavigationStack {
            Form {
                Section("Plataforma") {
                    Picker("Destino", selection: $configuration.destination) {
                        ForEach(StreamDestination.allCases) { destination in
                            Text(destination.rawValue).tag(destination)
                        }
                    }
                    Text(configuration.destination.guidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Servidor") {
                    TextField("rtmps://servidor/app", text: $configuration.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("Clave de transmisión", text: $configuration.streamKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Label(
                        configuration.isValid ? "Configuración válida" : "Faltan la URL o la clave",
                        systemImage: configuration.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(configuration.isValid ? .green : .orange)
                }

                Section("Calidad") {
                    Picker(
                        "Resolución del lienzo",
                        selection: Binding(
                            get: { configuration.resolutionPreset },
                            set: { configuration.resolutionPreset = $0 }
                        )
                    ) {
                        ForEach(StudioResolutionPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }

                    HStack {
                        TextField("Ancho", value: $configuration.outputWidth, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("×")
                            .foregroundStyle(.secondary)
                        TextField("Alto", value: $configuration.outputHeight, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .onSubmit { configuration.normalizeResolution() }

                    Text("El lienzo usa estos píxeles, pero Vista previa y Programa se ajustan dentro de sus paneles como en OBS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker("Fotogramas por segundo", selection: $configuration.framesPerSecond) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Video: \(configuration.bitrate / 1_000_000) Mbps")
                        Slider(
                            value: Binding(
                                get: { Double(configuration.bitrate) },
                                set: { configuration.bitrate = Int($0) }
                            ),
                            in: 2_000_000...8_000_000,
                            step: 500_000
                        )
                    }
                }

                Section("Pantalla externa") {
                    Label("Compatible con pantalla extendida y Stage Manager", systemImage: "display.2")
                    Text("Para mantener Programa activo, deja StudioPad visible en una ventana. Si abandonas completamente la app, iPadOS puede suspenderla y congelar la salida externa.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("La clave queda guardada en el llavero protegido de este iPad. No la compartas ni la incluyas en capturas de pantalla.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
