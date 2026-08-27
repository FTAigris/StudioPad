import Combine
import Foundation
import Network

/// Entrega la configuración a la extensión ReplayKit por la interfaz local.
/// Solo está activo mientras la pantalla de emisión permanece visible.
final class BroadcastConfigurationRelay: ObservableObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "StudioPad.configuration-relay")
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var expiration: DispatchWorkItem?

    func start(streamURL: URL?, videoBitRate: Int, framesPerSecond: Int) {
        stop()
        guard let streamURL else { return }

        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: BroadcastConstants.configurationRelayPort)!,
            using: .udp
        )
        let configuration = BroadcastConfigurationPayload(
            streamURL: streamURL.absoluteString,
            videoBitRate: videoBitRate,
            framesPerSecond: framesPerSecond
        )
        guard let payload = try? JSONEncoder().encode(configuration) else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)

        timer.schedule(deadline: .now(), repeating: .milliseconds(350))
        timer.setEventHandler {
            connection.send(content: payload, completion: .contentProcessed { _ in })
        }

        self.connection = connection
        self.timer = timer
        connection.start(queue: queue)
        timer.resume()

        let expiration = DispatchWorkItem { [weak self] in
            self?.stop()
        }
        self.expiration = expiration
        queue.asyncAfter(deadline: .now() + .seconds(15), execute: expiration)
    }

    func stop() {
        expiration?.cancel()
        expiration = nil
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        connection?.cancel()
        connection = nil
    }

    deinit {
        stop()
    }
}
