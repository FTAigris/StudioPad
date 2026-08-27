import Foundation
import Network

final class BroadcastConfigurationReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "StudioPad.configuration-receiver")
    private let listener: NWListener
    private let onConfiguration: @Sendable (BroadcastConfigurationPayload) -> Void
    private var finished = false

    init(onConfiguration: @escaping @Sendable (BroadcastConfigurationPayload) -> Void) throws {
        listener = try NWListener(
            using: .udp,
            on: NWEndpoint.Port(rawValue: BroadcastConstants.configurationRelayPort)!
        )
        self.onConfiguration = onConfiguration
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: queue)
            connection.receiveMessage { [weak self] data, _, _, _ in
                defer { connection.cancel() }
                guard let self,
                      let data,
                      let payload = try? JSONDecoder().decode(
                        BroadcastConfigurationPayload.self,
                        from: data
                      ),
                      payload.validatedURL != nil else { return }
                finish(with: payload)
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func finish(with payload: BroadcastConfigurationPayload) {
        guard !finished else { return }
        finished = true
        listener.cancel()
        onConfiguration(payload)
    }
}
