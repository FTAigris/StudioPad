import AVFoundation
import HaishinKit
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let model: CameraStudioModel

    final class Coordinator {
        let model: CameraStudioModel

        init(model: CameraStudioModel) {
            self.model = model
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = AVLayerVideoGravity.resizeAspectFill
        model.attachPreview(view)
        return view
    }

    func updateUIView(_ uiView: MTHKView, context: Context) {}

    static func dismantleUIView(_ uiView: MTHKView, coordinator: Coordinator) {
        coordinator.model.detachPreview(uiView)
    }
}
