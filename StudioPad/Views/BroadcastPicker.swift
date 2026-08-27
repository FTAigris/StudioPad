import ReplayKit
import SwiftUI

struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = uploadExtensionIdentifier()
        picker.showsMicrophoneButton = true
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}

    private func uploadExtensionIdentifier() -> String? {
        if let plugInsURL = Bundle.main.builtInPlugInsURL,
           let plugIns = try? FileManager.default.contentsOfDirectory(
            at: plugInsURL,
            includingPropertiesForKeys: nil
           ) {
            for plugInURL in plugIns where plugInURL.pathExtension == "appex" {
                guard let bundle = Bundle(url: plugInURL),
                      let extensionInfo = bundle.object(
                        forInfoDictionaryKey: "NSExtension"
                      ) as? [String: Any],
                      let extensionPoint = extensionInfo[
                        "NSExtensionPointIdentifier"
                      ] as? String,
                      extensionPoint == "com.apple.broadcast-services-upload" else { continue }
                return bundle.bundleIdentifier
            }
        }

        return Bundle.main.bundleIdentifier.map { $0 + ".ScreenBroadcast" }
    }
}
