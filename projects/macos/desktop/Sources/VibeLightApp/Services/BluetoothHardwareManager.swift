import CoreBluetooth
import Foundation
import VibeLightCore

@MainActor
final class BluetoothHardwareManager: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private final class PeripheralContext {
        let peripheral: CBPeripheral
        var statusCharacteristic: CBCharacteristic?
        var healthCharacteristic: CBCharacteristic?

        init(peripheral: CBPeripheral) {
            self.peripheral = peripheral
        }
    }

    private let serviceUUID = CBUUID(string: "7d8f0001-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let statusCharacteristicUUID = CBUUID(string: "7d8f0002-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let healthCharacteristicUUID = CBUUID(string: "7d8f0003-7b9a-4f0b-9e8a-8b4c2c7f1000")

    private var central: CBCentralManager?
    private var peripheralsByID: [String: CBPeripheral] = [:]
    private var contextsByID: [String: PeripheralContext] = [:]
    private var connectionAttemptIDs: Set<String> = []
    private var manualDisconnectIDs: Set<String> = []
    private var shouldScanWhenPoweredOn = false
    private var shouldAutoConnectDevices = false
    private var shouldClearDevicesWhenPoweredOn = false
    private let store = HardwareDeviceStore()

    private let onDevicesChanged: ([HardwareDevice]) -> Void
    private let onStateChanged: (HardwareConnectionState, Bool, String) -> Void
    private let onHealthChanged: (String, HealthPacket?) -> Void
    private let latestPacketData: (Int) -> Data?
    private let autoConnectEnabled: () -> Bool

    init(
        onDevicesChanged: @escaping ([HardwareDevice]) -> Void,
        onStateChanged: @escaping (HardwareConnectionState, Bool, String) -> Void,
        onHealthChanged: @escaping (String, HealthPacket?) -> Void,
        latestPacketData: @escaping (Int) -> Data?,
        autoConnectEnabled: @escaping () -> Bool
    ) {
        self.onDevicesChanged = onDevicesChanged
        self.onStateChanged = onStateChanged
        self.onHealthChanged = onHealthChanged
        self.latestPacketData = latestPacketData
        self.autoConnectEnabled = autoConnectEnabled
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var canWriteStatus: Bool {
        contextsByID.values.contains { context in
            context.peripheral.state == .connected && context.statusCharacteristic != nil
        }
    }

    func startScan(autoConnectDevices: Bool = false, clearDevices: Bool = false) {
        guard let central else { return }

        switch central.state {
        case .poweredOn:
            break
        case .unknown, .resetting:
            shouldScanWhenPoweredOn = true
            shouldAutoConnectDevices = autoConnectDevices
            shouldClearDevicesWhenPoweredOn = clearDevices
            publish("等待蓝牙就绪后扫描。")
            return
        default:
            shouldScanWhenPoweredOn = false
            shouldAutoConnectDevices = false
            shouldClearDevicesWhenPoweredOn = false
            store.fail(central.state.recoveryMessage)
            publish(central.state.recoveryMessage)
            return
        }

        shouldScanWhenPoweredOn = false
        shouldAutoConnectDevices = autoConnectDevices
        shouldClearDevicesWhenPoweredOn = false
        store.startScanning(clearDevices: clearDevices)
        publish(autoConnectDevices ? "正在扫描并连接所有 VibeLight 设备..." : "正在扫描 VibeLight 设备...")
        central.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true,
        ])
    }

    func stopScan() {
        shouldScanWhenPoweredOn = false
        shouldAutoConnectDevices = false
        shouldClearDevicesWhenPoweredOn = false
        central?.stopScan()
        store.stopScanning()
        publish("已停止扫描。")
    }

    func connect(deviceID: String) {
        guard let peripheral = peripheralsByID[deviceID] else {
            store.fail("找不到设备。")
            publish()
            return
        }
        guard peripheral.state == .disconnected, !connectionAttemptIDs.contains(deviceID) else { return }

        connectionAttemptIDs.insert(deviceID)
        store.markConnecting(deviceID)
        publish("正在连接 \(peripheral.name ?? "VibeLight")...")
        central?.connect(peripheral)
    }

    func disconnect() {
        shouldAutoConnectDevices = false
        shouldClearDevicesWhenPoweredOn = false
        let deviceIDs = Set(contextsByID.keys).union(connectionAttemptIDs)
        manualDisconnectIDs.formUnion(deviceIDs)
        for deviceID in deviceIDs {
            if let peripheral = peripheralsByID[deviceID] {
                central?.cancelPeripheralConnection(peripheral)
            }
            onHealthChanged(deviceID, nil)
        }
        contextsByID.removeAll()
        connectionAttemptIDs.removeAll()
        store.disconnect()
        publish("已断开全部设备。")
    }

    @discardableResult
    func sendLatestPacket() -> Bool {
        sendPacketData(messageWhenMissing: "没有可写入的设备或状态包。") { [latestPacketData] maximumWriteLength in
            latestPacketData(maximumWriteLength)
        }
    }

    @discardableResult
    func sendPacket(_ packet: StatusPacket) -> Bool {
        sendPacketData(messageWhenMissing: "没有可写入的设备。") { maximumWriteLength in
            try? packet.encodedJSON(maximumWriteLength: maximumWriteLength)
        }
    }

    private func sendPacketData(
        messageWhenMissing: String,
        dataProvider: (Int) -> Data?
    ) -> Bool {
        var writeCount = 0
        for context in contextsByID.values where context.peripheral.state == .connected {
            guard let characteristic = context.statusCharacteristic else { continue }
            let maximumWriteLength = context.peripheral.maximumWriteValueLength(for: .withResponse)
            guard let data = dataProvider(maximumWriteLength) else { continue }
            context.peripheral.writeValue(data, for: characteristic, type: .withResponse)
            writeCount += 1
        }

        guard writeCount > 0 else {
            publish(messageWhenMissing)
            return false
        }
        publish("已同步状态到 \(writeCount) 个设备。")
        return true
    }

    func readHealthPacket() {
        var readCount = 0
        for context in contextsByID.values where context.peripheral.state == .connected {
            guard let characteristic = context.healthCharacteristic else { continue }
            context.peripheral.readValue(for: characteristic)
            readCount += 1
        }
        if readCount == 0 {
            publish("没有可读取的健康状态特征。")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if shouldScanWhenPoweredOn {
                startScan(
                    autoConnectDevices: shouldAutoConnectDevices,
                    clearDevices: shouldClearDevicesWhenPoweredOn
                )
            } else {
                publish("蓝牙已就绪。")
            }
        case .unknown, .resetting:
            publish(shouldScanWhenPoweredOn ? "等待蓝牙就绪后扫描。" : central.state.recoveryMessage)
        default:
            shouldScanWhenPoweredOn = false
            shouldAutoConnectDevices = false
            shouldClearDevicesWhenPoweredOn = false
            for deviceID in contextsByID.keys {
                onHealthChanged(deviceID, nil)
            }
            contextsByID.removeAll()
            connectionAttemptIDs.removeAll()
            store.disconnect()
            store.fail(central.state.recoveryMessage)
            publish(central.state.recoveryMessage)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "VibeLight"
        guard name.hasPrefix("VibeLight") else { return }

        let id = peripheral.identifier.uuidString
        peripheralsByID[id] = peripheral
        store.upsert(HardwareDevice(id: id, name: name, rssi: RSSI.intValue))
        publish("发现 \(store.devices.count) 个 VibeLight 设备。")

        if shouldAutoConnectDevices {
            connect(deviceID: id)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let id = peripheral.identifier.uuidString
        connectionAttemptIDs.remove(id)
        contextsByID[id] = PeripheralContext(peripheral: peripheral)
        peripheral.delegate = self
        store.connect(id)
        publish("已连接 \(peripheral.name ?? "VibeLight")，正在发现服务。")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        connectionAttemptIDs.remove(id)
        contextsByID.removeValue(forKey: id)
        onHealthChanged(id, nil)
        store.fail(id, message: error?.localizedDescription ?? "连接失败")
        publish()
        let wasManual = manualDisconnectIDs.remove(id) != nil
        if !wasManual {
            recoverConnectionIfNeeded(after: .connectFailure)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        contextsByID.removeValue(forKey: id)
        connectionAttemptIDs.remove(id)
        onHealthChanged(id, nil)
        store.disconnect(id)

        let wasManual = manualDisconnectIDs.remove(id) != nil
        if wasManual {
            publish("\(peripheral.name ?? "设备") 已断开。")
        } else {
            publish(error?.localizedDescription ?? "\(peripheral.name ?? "设备") 已断开，正在准备重新连接。")
            recoverConnectionIfNeeded(after: .unexpectedDisconnect)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            store.fail(peripheral.identifier.uuidString, message: error.localizedDescription)
            publish()
            return
        }
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([statusCharacteristicUUID, healthCharacteristicUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        if let error {
            store.fail(id, message: error.localizedDescription)
            publish()
            return
        }
        guard let context = contextsByID[id] else { return }

        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == statusCharacteristicUUID {
                context.statusCharacteristic = characteristic
            }
            if characteristic.uuid == healthCharacteristicUUID {
                context.healthCharacteristic = characteristic
            }
        }

        if let healthCharacteristic = context.healthCharacteristic {
            peripheral.readValue(for: healthCharacteristic)
        }
        guard context.statusCharacteristic != nil else {
            publish("\(peripheral.name ?? "设备") 未找到状态写入特征。")
            return
        }
        publish("\(peripheral.name ?? "设备") 已就绪。")
        sendLatestPacket()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            publish("状态写入失败：\(error.localizedDescription)")
            return
        }
        if characteristic.uuid == statusCharacteristicUUID,
           let healthCharacteristic = contextsByID[peripheral.identifier.uuidString]?.healthCharacteristic {
            peripheral.readValue(for: healthCharacteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == healthCharacteristicUUID else { return }
        if let error {
            publish("读取健康状态失败：\(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else {
            publish("健康状态为空。")
            return
        }

        do {
            let health = try JSONDecoder().decode(HealthPacket.self, from: data)
            onHealthChanged(peripheral.identifier.uuidString, health)
            publish("已读取 \(peripheral.name ?? "设备") 健康状态。")
        } catch {
            publish("健康状态解析失败：\(error.localizedDescription)")
        }
    }

    private func publish(_ message: String? = nil) {
        let devices = store.devices
        let connectionState = store.connectionState
        let isScanning = store.isScanning
        let hardwareMessage = message ?? connectionState.title

        Task { @MainActor [onDevicesChanged, onStateChanged] in
            onDevicesChanged(devices)
            onStateChanged(connectionState, isScanning, hardwareMessage)
        }
    }

    private func recoverConnectionIfNeeded(after event: HardwareReconnectPolicy.Event) {
        let policy = HardwareReconnectPolicy(autoConnectEnabled: autoConnectEnabled())
        guard policy.action(after: event) == .scanAndAutoConnectDevices else { return }
        if store.isScanning {
            shouldAutoConnectDevices = true
        } else {
            startScan(autoConnectDevices: true)
        }
    }
}

private extension CBManagerState {
    var recoveryMessage: String {
        switch self {
        case .unknown: "正在检查蓝牙状态。"
        case .resetting: "蓝牙正在重置，稍后会自动继续扫描。"
        case .unsupported: "这台 Mac 不支持 BLE，无法扫描 VibeLight 设备。"
        case .unauthorized: "未获得蓝牙权限。请在系统设置 > 隐私与安全性 > 蓝牙中允许 Vibe Light。"
        case .poweredOff: "蓝牙已关闭。请先打开系统蓝牙后再扫描。"
        case .poweredOn: "蓝牙已就绪。"
        @unknown default: "蓝牙处于未知状态，请稍后重试。"
        }
    }
}
