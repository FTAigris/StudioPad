import Combine
import SwiftUI
import UIKit

struct StudioOutputDestination: Identifiable, Hashable {
    static let iPadID = "ipad"

    let id: String
    let name: String
    let detail: String
    let isExternal: Bool

    static let iPad = StudioOutputDestination(
        id: iPadID,
        name: "Solo en el iPad",
        detail: "Programa dentro de StudioPad",
        isExternal: false
    )
}

@MainActor
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published private(set) var destinations: [StudioOutputDestination] = [.iPad]
    @Published var selectedDestinationID = StudioOutputDestination.iPadID

    private var externalDestinations: [String: StudioOutputDestination] = [:]

    private init() {}

    func connect(sessionID: String, screen: UIScreen) {
        let existingNumber = externalDestinations[sessionID]
            .flatMap { destination in
                Int(destination.name.components(separatedBy: " ").last ?? "")
            }
        let number = existingNumber ?? (externalDestinations.count + 1)
        let pixels = screen.nativeBounds.size
        externalDestinations[sessionID] = StudioOutputDestination(
            id: sessionID,
            name: "Pantalla externa \(number)",
            detail: "\(Int(pixels.width)) × \(Int(pixels.height))",
            isExternal: true
        )
        rebuildDestinations()
    }

    func disconnect(sessionID: String) {
        externalDestinations.removeValue(forKey: sessionID)
        if selectedDestinationID == sessionID {
            selectedDestinationID = StudioOutputDestination.iPadID
        }
        rebuildDestinations()
    }

    func select(_ destinationID: String) {
        guard destinations.contains(where: { $0.id == destinationID }) else {
            selectedDestinationID = StudioOutputDestination.iPadID
            return
        }
        selectedDestinationID = destinationID
    }

    var selectedDestination: StudioOutputDestination {
        destinations.first(where: { $0.id == selectedDestinationID }) ?? .iPad
    }

    private func rebuildDestinations() {
        destinations = [.iPad] + externalDestinations.values.sorted { $0.name < $1.name }
    }
}

@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var sessionID: String?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let windowScene = scene as? UIWindowScene else { return }

        let sessionID = session.persistentIdentifier
        self.sessionID = sessionID
        ExternalDisplayManager.shared.connect(sessionID: sessionID, screen: windowScene.screen)

        let content = ExternalProgramView(sessionID: sessionID)
            .environmentObject(StudioStore.shared)
            .environmentObject(ExternalDisplayManager.shared)
            .environmentObject(StreamConfiguration.shared)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: content)
        window.backgroundColor = .black
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let sessionID {
            ExternalDisplayManager.shared.disconnect(sessionID: sessionID)
        }
        window = nil
    }
}
