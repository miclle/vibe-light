import Foundation

public struct HardwareDevice: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var rssi: Int
    public var lastSeen: Date
    public var connectionState: HardwareDeviceConnectionState

    public init(
        id: String,
        name: String,
        rssi: Int,
        lastSeen: Date = Date(),
        connectionState: HardwareDeviceConnectionState = .disconnected
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.connectionState = connectionState
    }
}

public enum HardwareDeviceConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    public var title: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "连接中"
        case .connected: "已连接"
        case .failed: "连接失败"
        }
    }
}

public enum HardwareConnectionState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)

    public var title: String {
        switch self {
        case .disconnected: "未连接"
        case .scanning: "扫描中"
        case .connecting: "连接中"
        case .connected: "已连接"
        case .failed: "连接失败"
        }
    }

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    public var isConnecting: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }
}

public final class HardwareDeviceStore {
    public private(set) var devices: [HardwareDevice]
    public private(set) var connectionState: HardwareConnectionState
    public private(set) var isScanning: Bool
    private var globalFailureMessage: String?

    public var connectedDeviceIDs: Set<String> {
        Set(devices.lazy.filter { $0.connectionState == .connected }.map(\.id))
    }

    public init(
        devices: [HardwareDevice] = [],
        connectionState: HardwareConnectionState = .disconnected,
        isScanning: Bool = false
    ) {
        self.devices = devices
        self.connectionState = connectionState
        self.isScanning = isScanning
    }

    public func startScanning(clearDevices: Bool = false) {
        if clearDevices {
            devices.removeAll { device in
                device.connectionState != .connected && device.connectionState != .connecting
            }
        }
        isScanning = true
        globalFailureMessage = nil
        refreshAggregateState()
    }

    public func stopScanning() {
        isScanning = false
        refreshAggregateState()
    }

    public func upsert(_ device: HardwareDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            var updated = device
            updated.connectionState = devices[index].connectionState
            devices[index] = updated
        } else {
            devices.append(device)
        }
        devices.sort { $0.rssi > $1.rssi }
    }

    public func connect(_ id: String) {
        updateDevice(id) { $0.connectionState = .connected }
        globalFailureMessage = nil
        refreshAggregateState()
    }

    public func markConnecting(_ id: String) {
        updateDevice(id) { $0.connectionState = .connecting }
        globalFailureMessage = nil
        refreshAggregateState()
    }

    public func disconnect(_ id: String) {
        updateDevice(id) { $0.connectionState = .disconnected }
        refreshAggregateState()
    }

    public func disconnect() {
        for index in devices.indices {
            devices[index].connectionState = .disconnected
        }
        globalFailureMessage = nil
        refreshAggregateState()
    }

    public func fail(_ id: String, message: String) {
        updateDevice(id) { $0.connectionState = .failed(message) }
        refreshAggregateState()
    }

    public func fail(_ message: String) {
        isScanning = false
        globalFailureMessage = message
        refreshAggregateState()
    }

    private func updateDevice(_ id: String, body: (inout HardwareDevice) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        body(&devices[index])
    }

    private func refreshAggregateState() {
        if let connected = devices
            .filter({ $0.connectionState == .connected })
            .sorted(by: { $0.id < $1.id })
            .first {
            connectionState = .connected(connected.id)
            return
        }
        if let connecting = devices
            .filter({ $0.connectionState == .connecting })
            .sorted(by: { $0.id < $1.id })
            .first {
            connectionState = .connecting(connecting.id)
            return
        }
        if isScanning {
            connectionState = .scanning
            return
        }
        if let globalFailureMessage {
            connectionState = .failed(globalFailureMessage)
            return
        }
        if let failed = devices.compactMap({ device -> String? in
            guard case let .failed(message) = device.connectionState else { return nil }
            return message
        }).first {
            connectionState = .failed(failed)
            return
        }
        connectionState = .disconnected
    }
}
