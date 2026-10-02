import Foundation
import Network
import os

// Says when a network that isn't marked as costly comes up, so a model install waiting for one needn't poll (#87).
@MainActor
public protocol InexpensiveNetworkWatching: AnyObject {
    // `onAvailable` runs each time such a network appears after there was none. The network in use when watching
    // starts doesn't count: the install that started the watch has just tried it.
    func start(onAvailable: @escaping @MainActor () -> Void)
    func stop()
}

// Turns path readings into "a usable network has just come up": the first reading only sets where it starts.
public struct InexpensiveNetworkTransitions: Equatable, Sendable {
    private var wasUsable: Bool?

    public init() {}

    public static func isUsable(isSatisfied: Bool, isExpensive: Bool, isConstrained: Bool) -> Bool {
        isSatisfied && !isExpensive && !isConstrained
    }

    public mutating func update(isUsable: Bool) -> Bool {
        defer { wasUsable = isUsable }
        return wasUsable == false && isUsable
    }
}

// NWPathMonitor wakes only when the path changes, so watching costs nothing while the network stays as it is.
@MainActor
public final class NWPathInexpensiveNetworkWatcher: InexpensiveNetworkWatching {
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.sorla.app.network-path", qos: .utility)

    public init() {}

    public func start(onAvailable: @escaping @MainActor () -> Void) {
        stop()
        let monitor = NWPathMonitor()
        let transitions = OSAllocatedUnfairLock(initialState: InexpensiveNetworkTransitions())
        monitor.pathUpdateHandler = { path in
            let isUsable = InexpensiveNetworkTransitions.isUsable(
                isSatisfied: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            guard transitions.withLock({ $0.update(isUsable: isUsable) }) else { return }
            Task { @MainActor in onAvailable() }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
