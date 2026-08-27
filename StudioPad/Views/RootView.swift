import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            CameraStudioView()
                .tabItem {
                    Label("Cámara", systemImage: "video.fill")
                }

            ScreenStudioView()
                .tabItem {
                    Label("Pantalla", systemImage: "rectangle.inset.filled")
                }

            SettingsView()
                .tabItem {
                    Label("Transmisión", systemImage: "slider.horizontal.3")
                }
        }
        .tint(.red)
    }
}

