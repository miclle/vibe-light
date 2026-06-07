import CoreBluetooth
import Foundation
import VibeLightCore

final class BluetoothHardwareManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let serviceUUID = CBUUID(string: "7d8f0001-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let statusCharacteristicUUID = CBUUID(string: "7d8f0002-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let healthCharacteristicUUID = CBUUID(string: "7d8f0003-7b9a-4f0b-9e8a-8b4c2c7f1000")

    private var central: CBCentralManager?
    private var peripheralsByID: [String: CBPeripheral] = [:]
    private var statusCharacteristic: CBCharacteristic?
    private var healthCharacteristic: CBCharacteristic?
    private var connectedPeripheral: CBPeripheral?
    private var shouldScanWhenPoweredOn = false
    private var shouldAutoConnectFirstDevice = false
    private let store = HardwareDeviceStore()

    private let onDevicesChanged: ([HardwareDevice]) -> Void
    private let onStateChanged: (HardwareConnectionState, Bool, String) -> Void
    private let onHealthChanged: (HealthPacket?) -> Void
    private let latestPacketData: () -> Data?

    init(
        onDevicesChanged: @escaping ([HardwareDevice]) -> Void,
        onStateChanged: @escaping (HardwareConnectionState, Bool, String) -> Void,
        onHealthChanged: @escaping (HealthPacket?) -> Void,
        latestPacketData: @escaping () -> Data?
    ) {
        self.onDevicesChanged = onDevicesChanged
        self.onStateChanged = onStateChanged
        self.onHealthChanged = onHealthChanged
        self.latestPacketData = latestPacketData
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var canWriteStatus: Bool {
        connectedPeripheral != nil && statusCharacteristic != nil
    }

    func startScan(autoConnectFirstDevice: Bool = false) {
        guard let central else { return }
        guard central.state == .poweredOn else {
            shouldScanWhenPoweredOn = true
            shouldAutoConnectFirstDevice = autoConnectFirstDevice
            publish("等待蓝牙就绪后扫描。")
            return
        }

        shouldScanWhenPoweredOn = false
        shouldAutoConnectFirstDevice = autoConnectFirstDevice
        store.startScanning()
        publish("正在扫描 VibeLight 设备...")
        central.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true,
        ])
    }

    func stopScan() {
        shouldScanWhenPoweredOn = false
        shouldAutoConnectFirstDevice = false
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

        central?.stopScan()
        shouldAutoConnectFirstDevice = false
        store.markConnecting(deviceID)
        publish("正在连接 \(peripheral.name ?? "VibeLight")...")
        central?.connect(peripheral)
    }

    func disconnect() {
        if let connectedPeripheral {
            central?.cancelPeripheralConnection(connectedPeripheral)
        }
        connectedPeripheral = nil
        statusCharacteristic = nil
        healthCharacteristic = nil
        shouldAutoConnectFirstDevice = false
        onHealthChanged(nil)
        store.disconnect()
        publish("已断开设备。")
    }

    @discardableResult
    func sendLatestPacket() -> Bool {
        guard let data = latestPacketData(),
              let connectedPeripheral,
              let statusCharacteristic else {
            publish("没有可写入的设备或状态包。")
            return false
        }

        connectedPeripheral.writeValue(data, for: statusCharacteristic, type: .withResponse)
        publish("已同步最近状态包。")
        return true
    }

    func readHealthPacket() {
        guard let connectedPeripheral,
              let healthCharacteristic else {
            publish("没有可读取的健康状态特征。")
            return
        }

        connectedPeripheral.readValue(for: healthCharacteristic)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if shouldScanWhenPoweredOn {
                startScan(autoConnectFirstDevice: shouldAutoConnectFirstDevice)
            } else {
                publish("蓝牙已就绪。")
            }
        case .unknown, .resetting:
            publish(shouldScanWhenPoweredOn ? "等待蓝牙就绪后扫描。" : "蓝牙\(central.state.description)。")
        default:
            shouldScanWhenPoweredOn = false
            shouldAutoConnectFirstDevice = false
            store.fail("蓝牙不可用：\(central.state.description)")
            publish()
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

        if shouldAutoConnectFirstDevice {
            connect(deviceID: id)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        store.connect(peripheral.identifier.uuidString)
        publish("已连接 \(peripheral.name ?? "VibeLight")，正在发现服务。")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        store.fail(error?.localizedDescription ?? "连接失败")
        publish()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripheral = nil
        statusCharacteristic = nil
        healthCharacteristic = nil
        onHealthChanged(nil)
        store.disconnect()
        publish(error?.localizedDescription ?? "设备已断开。")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            store.fail(error.localizedDescription)
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
        if let error {
            store.fail(error.localizedDescription)
            publish()
            return
        }

        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == statusCharacteristicUUID {
                statusCharacteristic = characteristic
            }
            if characteristic.uuid == healthCharacteristicUUID {
                healthCharacteristic = characteristic
            }
        }

        if healthCharacteristic != nil {
            readHealthPacket()
        }

        guard statusCharacteristic != nil else {
            publish("未找到状态写入特征。")
            return
        }

        publish("设备已就绪，可以写入状态。")
        sendLatestPacket()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            publish("状态写入失败：\(error.localizedDescription)")
            return
        }

        if characteristic.uuid == statusCharacteristicUUID {
            readHealthPacket()
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
            onHealthChanged(health)
            publish("已读取设备健康状态。")
        } catch {
            publish("健康状态解析失败：\(error.localizedDescription)")
        }
    }

    private func publish(_ message: String? = nil) {
        onDevicesChanged(store.devices)
        onStateChanged(
            store.connectionState,
            store.isScanning,
            message ?? store.connectionState.title
        )
    }
}

private extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: "未知"
        case .resetting: "重置中"
        case .unsupported: "不支持蓝牙"
        case .unauthorized: "未授权"
        case .poweredOff: "蓝牙已关闭"
        case .poweredOn: "蓝牙已开启"
        @unknown default: "未知状态"
        }
    }
}
