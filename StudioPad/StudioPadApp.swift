import HaishinKit
import RTMPHaishinKit
import SwiftUI

@main
struct StudioPadApp: App {
    @StateObject private var configuration = StreamConfiguration.shared
    @StateObject private var studio = StudioStore.shared
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    RootView()
                        .environmentObject(configuration)
                        .environmentObject(studio)
                } else {
                    LaunchView()
                }
            }
            .task {
                guard !isReady else { return }
                await SessionBuilderFactory.shared.register(RTMPSessionFactory())
                isReady = true
            }
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.red)
                Text("StudioPad")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
            }
        }
    }
}
