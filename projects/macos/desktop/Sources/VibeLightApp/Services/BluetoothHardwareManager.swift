import CoreBluetooth
import Foundation
import VibeLightCore

@MainActor
final class BluetoothHardwareManager: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private final class PeripheralContext {
        let peripheral: CBPeripheral
        var statusCharacteristic: CBCharacteristic?
        var healthCharacteristic: CBCharacteristic?
        var otaControlCharacteristic: CBCharacteristic?
        var otaDataCharacteristic: CBCharacteristic?
        var otaStatusCharacteristic: CBCharacteristic?
        var otaStatusNotificationsReady = false

        init(peripheral: CBPeripheral) {
            self.peripheral = peripheral
        }
    }

    private final class OTATransfer {
        enum ControlPhase: Equatable {
            case begin
            case finish
            case abort
        }

        let request: FirmwareOTARequest
        let file: FileHandle
        var controlPhase = ControlPhase.begin
        var offsets = FirmwareOTAOffsetTracker()
        var lastCommittedOffset = 0
        var beginPending = true
        var idlePollCount = 0
        var finishSent = false
        var shouldRetryFinishAfterReconnect = false
        var awaitingReboot = false
        var reconnectAttempts = 0
        var statusPollAttempts = 0
        var statusPollGeneration = 0
        var statusPollScheduled = false

        init(request: FirmwareOTARequest, file: FileHandle) {
            self.request = request
            self.file = file
        }
    }

    private let serviceUUID = CBUUID(string: "7d8f0001-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let statusCharacteristicUUID = CBUUID(string: "7d8f0002-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let healthCharacteristicUUID = CBUUID(string: "7d8f0003-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let otaServiceUUID = CBUUID(string: "7d8f0101-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let otaControlCharacteristicUUID = CBUUID(string: "7d8f0102-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let otaDataCharacteristicUUID = CBUUID(string: "7d8f0103-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let otaStatusCharacteristicUUID = CBUUID(string: "7d8f0104-7b9a-4f0b-9e8a-8b4c2c7f1000")
    private let otaStatusPollLimit = 80
    private let otaStatusPollInterval: TimeInterval = 0.25

    private var central: CBCentralManager?
    private var peripheralsByID: [String: CBPeripheral] = [:]
    private var contextsByID: [String: PeripheralContext] = [:]
    private var connectionAttemptIDs: Set<String> = []
    private var manualDisconnectIDs: Set<String> = []
    private var shouldScanWhenPoweredOn = false
    private var shouldAutoConnectDevices = false
    private var shouldClearDevicesWhenPoweredOn = false
    private var otaTransfer: OTATransfer?
    private let store = HardwareDeviceStore()

    private let onDevicesChanged: ([HardwareDevice]) -> Void
    private let onStateChanged: (HardwareConnectionState, Bool, String) -> Void
    private let onHealthChanged: (String, HealthPacket?) -> Void
    private let onOTAProgress: (FirmwareOTAProgress?) -> Void
    private let latestPacketData: (Int) -> Data?
    private let autoConnectEnabled: () -> Bool

    init(
        onDevicesChanged: @escaping ([HardwareDevice]) -> Void,
        onStateChanged: @escaping (HardwareConnectionState, Bool, String) -> Void,
        onHealthChanged: @escaping (String, HealthPacket?) -> Void,
        onOTAProgress: @escaping (FirmwareOTAProgress?) -> Void,
        latestPacketData: @escaping (Int) -> Data?,
        autoConnectEnabled: @escaping () -> Bool
    ) {
        self.onDevicesChanged = onDevicesChanged
        self.onStateChanged = onStateChanged
        self.onHealthChanged = onHealthChanged
        self.onOTAProgress = onOTAProgress
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
        if otaTransfer != nil {
            cancelFirmwareOTA()
        }
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
        for (deviceID, context) in contextsByID where context.peripheral.state == .connected {
            if otaTransfer?.request.deviceID == deviceID {
                continue
            }
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

    func canStartFirmwareOTA(deviceID: String) -> Bool {
        guard let context = contextsByID[deviceID] else { return false }
        return context.peripheral.state == .connected &&
            context.otaControlCharacteristic != nil &&
            context.otaDataCharacteristic != nil &&
            context.otaStatusCharacteristic != nil &&
            context.otaStatusNotificationsReady
    }

    func startFirmwareOTA(_ request: FirmwareOTARequest) {
        guard otaTransfer == nil else {
            reportOTAFailure(request: request, message: "已有无线更新正在进行。")
            return
        }
        guard request.imageSize > 0,
              request.imageSize <= Int(UInt32.max),
              request.sha256.count == 64 else {
            reportOTAFailure(request: request, message: "固件 OTA 元数据无效。")
            return
        }
        guard let context = contextsByID[request.deviceID],
              context.peripheral.state == .connected,
              let control = context.otaControlCharacteristic,
              let status = context.otaStatusCharacteristic,
              context.otaStatusNotificationsReady else {
            reportOTAFailure(request: request, message: "所选设备尚未发现完整的 OTA 特征。")
            return
        }
        do {
            let file = try FileHandle(forReadingFrom: request.applicationURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: request.applicationURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue == request.imageSize else {
                try file.close()
                reportOTAFailure(request: request, message: "固件文件大小与清单不一致。")
                return
            }
            otaTransfer = OTATransfer(request: request, file: file)
            onOTAProgress(progress(for: request, committedBytes: 0, stage: .preparing))
            context.peripheral.setNotifyValue(true, for: status)
            context.peripheral.writeValue(try FirmwareOTAControl.begin(request), for: control, type: .withResponse)
        } catch {
            reportOTAFailure(request: request, message: error.localizedDescription)
        }
    }

    func cancelFirmwareOTA() {
        guard let transfer = otaTransfer else { return }
        if let context = contextsByID[transfer.request.deviceID],
           let control = context.otaControlCharacteristic,
           context.peripheral.state == .connected {
            transfer.controlPhase = .abort
            if let data = try? FirmwareOTAControl.abort(sessionID: transfer.request.sessionID) {
                context.peripheral.writeValue(data, for: control, type: .withResponse)
            }
        }
        finishOTATransfer(stage: .cancelled)
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
            if let transfer = otaTransfer {
                reportOTAFailure(request: transfer.request, message: central.state.recoveryMessage)
            }
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
        peripheral.discoverServices([serviceUUID, otaServiceUUID])
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
        if !wasManual, otaTransfer?.request.deviceID == id {
            reconnectOTA(peripheral: peripheral, deviceID: id)
        } else if !wasManual {
            recoverConnectionIfNeeded(after: .connectFailure)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let id = peripheral.identifier.uuidString
        let reconnectsOTA = otaTransfer?.request.deviceID == id
        contextsByID.removeValue(forKey: id)
        connectionAttemptIDs.remove(id)
        onHealthChanged(id, nil)
        store.disconnect(id)

        let wasManual = manualDisconnectIDs.remove(id) != nil
        if wasManual {
            publish("\(peripheral.name ?? "设备") 已断开。")
        } else if reconnectsOTA {
            if let transfer = otaTransfer {
                cancelScheduledOTAStatusPoll(transfer)
                transfer.statusPollAttempts = 0
                transfer.offsets.prepareForReconnect()
                transfer.shouldRetryFinishAfterReconnect = FirmwareOTAReconnectPolicy.shouldRetryFinish(
                    finishSent: transfer.finishSent,
                    awaitingReboot: transfer.awaitingReboot
                )
            }
            publish("\(peripheral.name ?? "设备") 正在重启，准备恢复 OTA 会话。")
            reconnectOTA(peripheral: peripheral, deviceID: id)
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
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([statusCharacteristicUUID, healthCharacteristicUUID], for: service)
            } else if service.uuid == otaServiceUUID {
                peripheral.discoverCharacteristics(
                    [otaControlCharacteristicUUID, otaDataCharacteristicUUID, otaStatusCharacteristicUUID],
                    for: service
                )
            }
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
            if characteristic.uuid == otaControlCharacteristicUUID {
                context.otaControlCharacteristic = characteristic
            }
            if characteristic.uuid == otaDataCharacteristicUUID {
                context.otaDataCharacteristic = characteristic
            }
            if characteristic.uuid == otaStatusCharacteristicUUID {
                context.otaStatusCharacteristic = characteristic
                context.otaStatusNotificationsReady = false
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            }
        }

        if let healthCharacteristic = context.healthCharacteristic {
            peripheral.readValue(for: healthCharacteristic)
        }
        if otaTransfer?.request.deviceID == id,
           let otaStatusCharacteristic = context.otaStatusCharacteristic {
            peripheral.readValue(for: otaStatusCharacteristic)
        }
        if service.uuid == otaServiceUUID {
            if context.otaControlCharacteristic != nil,
               context.otaDataCharacteristic != nil,
               context.otaStatusCharacteristic != nil {
                publish("\(peripheral.name ?? "设备") 的无线更新服务已就绪。")
            }
            return
        }
        guard context.statusCharacteristic != nil else {
            publish("\(peripheral.name ?? "设备") 未找到状态写入特征。")
            return
        }
        publish("\(peripheral.name ?? "设备") 已就绪。")
        sendLatestPacket()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == otaControlCharacteristicUUID || characteristic.uuid == otaDataCharacteristicUUID {
            handleOTAWrite(peripheral: peripheral, characteristic: characteristic, error: error)
            return
        }
        if let error {
            publish("状态写入失败：\(error.localizedDescription)")
            return
        }
        if characteristic.uuid == statusCharacteristicUUID,
           let healthCharacteristic = contextsByID[peripheral.identifier.uuidString]?.healthCharacteristic {
            peripheral.readValue(for: healthCharacteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == otaStatusCharacteristicUUID,
              let context = contextsByID[peripheral.identifier.uuidString] else { return }
        context.otaStatusNotificationsReady = error == nil && characteristic.isNotifying
        if let transfer = otaTransfer,
           transfer.request.deviceID == peripheral.identifier.uuidString,
           !context.otaStatusNotificationsReady {
            let detail = error?.localizedDescription ?? "设备没有启用 OTA 状态通知。"
            reportOTAFailure(request: transfer.request, message: detail)
            return
        }
        if context.otaStatusNotificationsReady {
            peripheral.readValue(for: characteristic)
        } else if let error {
            publish("OTA 状态通知启用失败：\(error.localizedDescription)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == otaStatusCharacteristicUUID {
            handleOTAStatusUpdate(peripheral: peripheral, characteristic: characteristic, error: error)
            return
        }
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
            handleOTAHealth(peripheral: peripheral, health: health)
            publish("已读取 \(peripheral.name ?? "设备") 健康状态。")
        } catch {
            publish("健康状态解析失败：\(error.localizedDescription)")
        }
    }

    private func handleOTAWrite(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let transfer = otaTransfer,
              transfer.request.deviceID == peripheral.identifier.uuidString else { return }
        if let error {
            reportOTAFailure(request: transfer.request, message: "OTA 写入失败：\(error.localizedDescription)")
            return
        }
        if characteristic.uuid == otaDataCharacteristicUUID {
            if let status = contextsByID[transfer.request.deviceID]?.otaStatusCharacteristic {
                peripheral.readValue(for: status)
                scheduleOTAStatusPoll(peripheral: peripheral, transfer: transfer)
            }
            return
        }
        if transfer.controlPhase == .begin,
           let status = contextsByID[transfer.request.deviceID]?.otaStatusCharacteristic {
            peripheral.readValue(for: status)
        } else if transfer.controlPhase == .finish {
            scheduleOTAStatusPoll(peripheral: peripheral, transfer: transfer)
        }
    }

    private func handleOTAStatusUpdate(
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let transfer = otaTransfer,
              transfer.request.deviceID == peripheral.identifier.uuidString else { return }
        cancelScheduledOTAStatusPoll(transfer)
        if let error {
            reportOTAFailure(request: transfer.request, message: "读取 OTA 状态失败：\(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        do {
            let status = try JSONDecoder().decode(FirmwareOTAStatus.self, from: data)
            handleOTAStatus(status, peripheral: peripheral, transfer: transfer)
            if otaTransfer === transfer,
               FirmwareOTAStatusPolling.shouldPoll(
                   state: status.state,
                   pendingFrameEnd: transfer.offsets.pendingFrameEnd,
                   finishSent: transfer.finishSent,
                   awaitingReboot: transfer.awaitingReboot
               ) {
                scheduleOTAStatusPoll(peripheral: peripheral, transfer: transfer)
            }
        } catch {
            reportOTAFailure(request: transfer.request, message: "OTA 状态无法解析：\(error.localizedDescription)")
        }
    }

    private func handleOTAStatus(
        _ status: FirmwareOTAStatus,
        peripheral: CBPeripheral,
        transfer: OTATransfer
    ) {
        if (transfer.awaitingReboot || transfer.finishSent), status.state == .idle {
            transfer.awaitingReboot = true
            if let health = contextsByID[transfer.request.deviceID]?.healthCharacteristic {
                peripheral.readValue(for: health)
            }
            return
        }
        if status.state == .idle {
            if transfer.beginPending {
                pollOTAStatus(peripheral: peripheral, transfer: transfer)
            } else {
                restartOTAFromZero(peripheral: peripheral, transfer: transfer)
            }
            return
        }
        transfer.beginPending = false
        transfer.idlePollCount = 0
        guard status.v == 1, status.sessionId == transfer.request.sessionID else {
            reportOTAFailure(request: transfer.request, message: "设备返回了不同的 OTA 会话。")
            return
        }
        if status.state == .error {
            let detail = status.message ?? status.errorCode ?? "设备拒绝了固件"
            reportOTAFailure(request: transfer.request, message: detail)
            return
        }
        guard status.committedOffset >= 0,
              status.committedOffset <= transfer.request.imageSize else {
            reportOTAFailure(request: transfer.request, message: "设备返回了无效的固件偏移。")
            return
        }

        transfer.lastCommittedOffset = status.committedOffset
        transfer.offsets.observeCommittedOffset(status.committedOffset)

        switch status.state {
        case .ready, .receiving:
            onOTAProgress(progress(
                for: transfer.request,
                committedBytes: status.committedOffset,
                stage: .transferring
            ))
            if status.committedOffset == transfer.request.imageSize {
                if transfer.shouldRetryFinishAfterReconnect {
                    transfer.finishSent = false
                    transfer.shouldRetryFinishAfterReconnect = false
                }
                sendOTAFinish(peripheral: peripheral, transfer: transfer)
            } else if transfer.offsets.canSendNextFrame {
                sendNextOTAFrame(peripheral: peripheral, transfer: transfer)
            }
        case .verifying:
            onOTAProgress(progress(
                for: transfer.request,
                committedBytes: status.committedOffset,
                stage: .verifying
            ))
        case .rebooting:
            transfer.awaitingReboot = true
            onOTAProgress(progress(
                for: transfer.request,
                committedBytes: status.committedOffset,
                stage: .rebooting
            ))
        case .complete:
            break
        case .idle, .error:
            break
        }
    }

    private func sendNextOTAFrame(peripheral: CBPeripheral, transfer: OTATransfer) {
        guard let dataCharacteristic = contextsByID[transfer.request.deviceID]?.otaDataCharacteristic else {
            reportOTAFailure(request: transfer.request, message: "OTA 数据特征已不可用。")
            return
        }
        do {
            let maximumWriteLength = peripheral.maximumWriteValueLength(for: .withResponse)
            let payloadLength = min(
                FirmwareOTAFrame.maximumPayloadSize,
                maximumWriteLength - FirmwareOTAFrame.headerSize,
                transfer.request.imageSize - transfer.offsets.nextOffset
            )
            guard payloadLength > 0 else {
                throw FirmwareOTAEncodingError.writeValueTooShort
            }
            try transfer.file.seek(toOffset: UInt64(transfer.offsets.nextOffset))
            guard let payload = try transfer.file.read(upToCount: payloadLength),
                  payload.count == payloadLength else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let frame = try FirmwareOTAFrame.encode(
                sessionID: transfer.request.sessionID,
                offset: UInt32(transfer.offsets.nextOffset),
                payload: payload,
                maximumWriteLength: maximumWriteLength
            )
            transfer.offsets.stageFrame(endingAt: transfer.offsets.nextOffset + payload.count)
            resetOTAStatusPolling(transfer)
            peripheral.writeValue(frame, for: dataCharacteristic, type: .withResponse)
        } catch {
            reportOTAFailure(request: transfer.request, message: error.localizedDescription)
        }
    }

    private func restartOTAFromZero(peripheral: CBPeripheral, transfer: OTATransfer) {
        guard let control = contextsByID[transfer.request.deviceID]?.otaControlCharacteristic else { return }
        do {
            transfer.offsets = FirmwareOTAOffsetTracker()
            transfer.lastCommittedOffset = 0
            transfer.finishSent = false
            transfer.shouldRetryFinishAfterReconnect = false
            transfer.beginPending = true
            transfer.idlePollCount = 0
            resetOTAStatusPolling(transfer)
            transfer.controlPhase = .begin
            peripheral.writeValue(try FirmwareOTAControl.begin(transfer.request), for: control, type: .withResponse)
        } catch {
            reportOTAFailure(request: transfer.request, message: error.localizedDescription)
        }
    }

    private func pollOTAStatus(peripheral: CBPeripheral, transfer: OTATransfer) {
        guard transfer.idlePollCount < 20 else {
            reportOTAFailure(request: transfer.request, message: "设备没有启动 OTA 会话。")
            return
        }
        transfer.idlePollCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak peripheral] in
            guard let self, let peripheral,
                  self.otaTransfer === transfer,
                  let status = self.contextsByID[transfer.request.deviceID]?.otaStatusCharacteristic else { return }
            peripheral.readValue(for: status)
        }
    }

    private func resetOTAStatusPolling(_ transfer: OTATransfer) {
        cancelScheduledOTAStatusPoll(transfer)
        transfer.statusPollAttempts = 0
    }

    private func cancelScheduledOTAStatusPoll(_ transfer: OTATransfer) {
        transfer.statusPollGeneration += 1
        transfer.statusPollScheduled = false
    }

    private func scheduleOTAStatusPoll(peripheral: CBPeripheral, transfer: OTATransfer) {
        guard otaTransfer === transfer, !transfer.statusPollScheduled else { return }
        guard transfer.statusPollAttempts < otaStatusPollLimit else {
            reportOTAFailure(request: transfer.request, message: "设备 OTA 状态长时间未推进。")
            return
        }
        transfer.statusPollScheduled = true
        let generation = transfer.statusPollGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + otaStatusPollInterval) { [weak self, weak peripheral] in
            guard let self, let peripheral,
                  self.otaTransfer === transfer,
                  transfer.statusPollScheduled,
                  transfer.statusPollGeneration == generation else { return }
            transfer.statusPollScheduled = false
            transfer.statusPollAttempts += 1
            guard let status = self.contextsByID[transfer.request.deviceID]?.otaStatusCharacteristic else {
                self.reportOTAFailure(request: transfer.request, message: "OTA 状态特征已不可用。")
                return
            }
            peripheral.readValue(for: status)
        }
    }

    private func sendOTAFinish(peripheral: CBPeripheral, transfer: OTATransfer) {
        guard !transfer.finishSent,
              let control = contextsByID[transfer.request.deviceID]?.otaControlCharacteristic else { return }
        do {
            transfer.finishSent = true
            transfer.controlPhase = .finish
            resetOTAStatusPolling(transfer)
            peripheral.writeValue(
                try FirmwareOTAControl.finish(sessionID: transfer.request.sessionID),
                for: control,
                type: .withResponse
            )
        } catch {
            reportOTAFailure(request: transfer.request, message: error.localizedDescription)
        }
    }

    private func handleOTAHealth(peripheral: CBPeripheral, health: HealthPacket) {
        guard let transfer = otaTransfer,
              transfer.request.deviceID == peripheral.identifier.uuidString,
              transfer.awaitingReboot else { return }
        guard health.projectName == transfer.request.projectName,
              health.firmwareVersion == transfer.request.appVersion,
              health.rollbackState == "valid",
              health.signedUpdatesRequired == true else {
            reportOTAFailure(request: transfer.request, message: "设备重启后未运行目标固件，可能已自动回滚。")
            return
        }
        transfer.lastCommittedOffset = transfer.request.imageSize
        finishOTATransfer(stage: .complete)
        sendLatestPacket()
    }

    private func progress(
        for request: FirmwareOTARequest,
        committedBytes: Int,
        stage: FirmwareOTAProgressStage
    ) -> FirmwareOTAProgress {
        FirmwareOTAProgress(
            deviceID: request.deviceID,
            targetVersion: request.appVersion,
            committedBytes: committedBytes,
            totalBytes: request.imageSize,
            stage: stage
        )
    }

    private func reportOTAFailure(request: FirmwareOTARequest, message: String) {
        if otaTransfer?.request == request {
            finishOTATransfer(stage: .failed(message))
        } else {
            onOTAProgress(progress(for: request, committedBytes: 0, stage: .failed(message)))
        }
    }

    private func finishOTATransfer(stage: FirmwareOTAProgressStage) {
        guard let transfer = otaTransfer else { return }
        cancelScheduledOTAStatusPoll(transfer)
        try? transfer.file.close()
        onOTAProgress(progress(
            for: transfer.request,
            committedBytes: transfer.lastCommittedOffset,
            stage: stage
        ))
        otaTransfer = nil
    }

    private func reconnectOTA(peripheral: CBPeripheral, deviceID: String) {
        guard let transfer = otaTransfer, transfer.request.deviceID == deviceID else { return }
        guard transfer.reconnectAttempts < 5 else {
            reportOTAFailure(request: transfer.request, message: "设备重启后多次重连失败。")
            return
        }
        transfer.reconnectAttempts += 1
        connectionAttemptIDs.insert(deviceID)
        store.markConnecting(deviceID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.otaTransfer?.request.deviceID == deviceID else { return }
            self.central?.connect(peripheral)
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
