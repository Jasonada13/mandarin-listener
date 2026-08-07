import Foundation
import Network

@MainActor
final class NetworkMonitor {
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(
        label: "com.jasonadams.MandarinListener.network-monitor"
    )

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.onChange?(path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
