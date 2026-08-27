import SwiftUI

struct CameraStudioView: View {
    @EnvironmentObject private var configuration: StreamConfiguration
    @StateObject private var model = CameraStudioModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack(alignment: .topLeading) {
                    CameraPreview(model: model)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(.black, in: RoundedRectangle(cornerRadius: 24))

                    statusBadge
                        .padding(16)
                }

                HStack(spacing: 14) {
                    controlButton(
                        title: model.cameraLabel,
                        icon: "arrow.triangle.2.circlepath.camera",
                        action: model.flipCamera
                    )

                    controlButton(
                        title: model.isMuted ? "Activar audio" : "Silenciar",
                        icon: model.isMuted ? "mic.slash.fill" : "mic.fill",
                        action: model.toggleMute
                    )

                    controlButton(
                        title: model.isRecording ? "Guardar" : "Grabar",
                        icon: model.isRecording ? "stop.circle.fill" : "record.circle",
                        tint: model.isRecording ? .orange : .primary,
                        action: model.toggleRecording
                    )
                }

                Button(action: toggleLive) {
                    Label(
                        model.isLive ? "Finalizar transmisión" : "Iniciar transmisión",
                        systemImage: model.isLive ? "stop.fill" : "dot.radiowaves.left.and.right"
                    )
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isLive ? .gray : .red)
                .disabled(model.status == .preparing || model.status == .connecting || model.status == .stopping)

                if !configuration.isValid {
                    Label(
                        "Completa la URL y la clave en Transmisión antes de salir en directo.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }
            .padding()
            .navigationTitle("Cámara")
            .task {
                await model.prepare(using: configuration)
            }
            .onDisappear {
                if !model.isLive && !model.isRecording {
                    model.shutdown()
                }
            }
            .alert(
                "StudioPad",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("Aceptar", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isLive ? .red : .green)
                .frame(width: 10, height: 10)
            Text(model.status.label)
                .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func controlButton(
        title: String,
        icon: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func toggleLive() {
        if model.isLive {
            model.stopStreaming()
        } else {
            model.startStreaming(using: configuration)
        }
    }
}

