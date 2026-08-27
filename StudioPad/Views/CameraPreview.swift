import AVFoundation
import HaishinKit
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let model: CameraStudioModel

    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = AVLayerVideoGravity.resizeAspectFill
        model.attachPreview(view)
        return view
    }

    func updateUIView(_ uiView: MTHKView, context: Context) {}
}

