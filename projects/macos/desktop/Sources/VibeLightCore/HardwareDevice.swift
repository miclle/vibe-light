import Foundation

public struct HardwareDevice: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var rssi: Int
    public var lastSeen: Date

    public init(id: String, name: String, rssi: Int, lastSeen: Date = Date()) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.lastSeen = lastSeen
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
            devices.removeAll()
        }
        isScanning = true
        connectionState = .scanning
    }

    public func stopScanning() {
        isScanning = false
        if case .scanning = connectionState {
            connectionState = .disconnected
        }
    }

    public func upsert(_ device: HardwareDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        devices.sort { $0.rssi > $1.rssi }
    }

    public func connect(_ id: String) {
        isScanning = false
        connectionState = .connected(id)
    }

    public func markConnecting(_ id: String) {
        connectionState = .connecting(id)
    }

    public func disconnect() {
        connectionState = .disconnected
    }

    public func fail(_ message: String) {
        isScanning = false
        connectionState = .failed(message)
    }
}
