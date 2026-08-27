import SwiftUI

struct ScreenStudioView: View {
    @EnvironmentObject private var configuration: StreamConfiguration
    @StateObject private var configurationRelay = BroadcastConfigurationRelay()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.black.gradient)
                            .frame(height: 300)
                        VStack(spacing: 18) {
                            Image(systemName: "ipad.landscape")
                                .font(.system(size: 70, weight: .light))
                            Text("Emite la pantalla completa")
                                .font(.title2.bold())
                            Text("ReplayKit mantiene la emisión mientras usas juegos u otras aplicaciones.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 440)
                        }
                        .foregroundStyle(.white)
                    }

                    VStack(spacing: 12) {
                        BroadcastPicker()
                            .frame(width: 76, height: 76)
                            .accessibilityLabel("Iniciar transmisión de pantalla")
                            .allowsHitTesting(configuration.isValid)
                            .opacity(configuration.isValid ? 1 : 0.35)
                        Text("Toca el botón y elige StudioPad Pantalla")
                            .font(.headline)
                        if !configuration.isValid {
                            Label(
                                "Primero completa la pestaña Transmisión",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        instruction(1, "Configura la URL y la clave en la pestaña Transmisión.")
                        instruction(2, "Activa el micrófono si quieres incluir tu voz.")
                        instruction(3, "Pulsa Iniciar transmisión y abre el juego o aplicación que quieras mostrar.")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

                    Label(
                        "En iPadOS 26.6, pantalla y cámara funcionan como modos separados. La combinación simultánea se añadirá con la API de iPadOS 27.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Pantalla")
        }
        .onAppear {
            updateConfigurationRelay()
        }
        .onChange(of: configuration.serverURL) { _, _ in
            updateConfigurationRelay()
        }
        .onChange(of: configuration.streamKey) { _, _ in
            updateConfigurationRelay()
        }
        .onChange(of: configuration.bitrate) { _, _ in
            updateConfigurationRelay()
        }
        .onChange(of: configuration.framesPerSecond) { _, _ in
            updateConfigurationRelay()
        }
        .onDisappear {
            configurationRelay.stop()
        }
    }

    private func updateConfigurationRelay() {
        configurationRelay.start(
            streamURL: configuration.streamURL,
            videoBitRate: configuration.bitrate,
            framesPerSecond: configuration.framesPerSecond
        )
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(.red, in: Circle())
                .foregroundStyle(.white)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
