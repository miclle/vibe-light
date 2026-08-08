import AppKit
import Foundation
import VibeLightCore

@MainActor
final class VibeLightAppModel: ObservableObject {
    @Published var selectedTab: AppTab = .general
    @Published private(set) var currentState: DisplayState = .offline
    @Published private(set) var events: [VibeHookEvent] = []
    @Published private(set) var displaySnapshot: DisplaySnapshot?
    @Published private(set) var latestPacket: StatusPacket?
    @Published private(set) var agentStatuses: [AgentKind: AgentInstallationStatus] = [:]
    @Published private(set) var agentInstallMessage = "检查智能体 hook 配置。"
    @Published private(set) var hardwareDevices: [HardwareDevice] = []
    @Published private(set) var hardwareConnectionState: HardwareConnectionState = .disconnected
    @Published private(set) var hardwareHealthPacket: HealthPacket?
    @Published private(set) var hardwareHealthPackets: [String: HealthPacket] = [:]
    @Published private(set) var hardwareMessage = "未扫描设备。"
    @Published private(set) var isHardwareScanning = false
    @Published private(set) var firmwareSerialPorts: [String] = []
    @Published private(set) var firmwareBundles: [FirmwareBundle] = []
    @Published private(set) var firmwareBundle: FirmwareBundle?
    @Published private(set) var firmwareFlashMessage = "未检查固件包。"
    @Published private(set) var firmwareFlashLog = ""
    @Published private(set) var firmwareFlashProgress: FirmwareFlashProgressSnapshot?
    @Published private(set) var firmwareChipProbeResult: FirmwareChipProbeResult?
    @Published private(set) var firmwareFlashFailureKind: FirmwareFlashFailureKind?
    @Published private(set) var firmwareOTAProgress: FirmwareOTAProgress?
    @Published private(set) var didCompleteFirmwareFlash = false
    @Published private(set) var isFirmwareAwaitingReconnect = false
    @Published private(set) var isFirmwareChipProbing = false
    @Published private(set) var isFirmwareFlashing = false
    @Published var selectedFirmwareSerialPort: String? {
        didSet {
            if oldValue != selectedFirmwareSerialPort {
                clearFirmwareChipProbeConfirmation()
            }
        }
    }
    @Published var selectedFirmwareOTADeviceID: String?
    @Published var selectedFirmwareHardware: String? {
        didSet {
            guard oldValue != selectedFirmwareHardware else { return }
            firmwareBundle = firmwareBundles.first {
                $0.manifest.targetHardware == selectedFirmwareHardware
            }
            selectedFirmwareOTADeviceID = firmwareOTADeviceCandidates.first?.id
            clearFirmwareChipProbeConfirmation()
            if let firmwareBundle {
                firmwareFlashMessage = "已选择 \(firmwareBundle.manifest.targetHardware) 固件。"
            }
        }
    }
    @Published var launchAtLogin = false
    @Published var autoConnectDevice: Bool {
        didSet {
            preferences.autoConnectDevice = autoConnectDevice
        }
    }
    @Published var codex7dRedThresholdPercent: Int {
        didSet {
            let clamped = min(100, max(0, codex7dRedThresholdPercent))
            if clamped != codex7dRedThresholdPercent {
                codex7dRedThresholdPercent = clamped
                return
            }
            preferences.codex7dRedThresholdPercent = clamped
            refreshEvents()
        }
    }
    @Published var selectedManualState: DisplayState {
        didSet {
            preferences.selectedManualState = selectedManualState
        }
    }
    @Published var bridgeMessage = "等待 hook 事件..."

    var selectedFirmwareBLEDeviceName: String {
        firmwareBundle?.manifest.bleDeviceName ?? "VibeLight"
    }

    var firmwareOTADeviceCandidates: [HardwareDevice] {
        hardwareDevices.filter { device in
            device.connectionState == .connected && device.name == selectedFirmwareBLEDeviceName
        }
    }

    var isFirmwareOTAUpdating: Bool {
        guard let firmwareOTAProgress else { return false }
        switch firmwareOTAProgress.stage {
        case .preparing, .transferring, .verifying, .rebooting:
            return true
        case .complete, .failed, .cancelled:
            return false
        }
    }

    private let eventLog: EventLog
    private let agentInstaller: AgentInstaller
    private let preferences: VibeLightPreferences
    private let taskTracker: TaskTracker
    private let firmwareFlashProcessRunner: FirmwareFlashProcessRunner
    private var bluetoothManager: BluetoothHardwareManager?
    private var latestPacketData: Data?
    private var lastForwardedPacketData: Data?
    private var demoPacketHold = HardwareDemoPacketHold()
    private var didStartHardwareAutoConnect = false
    private var confirmedFirmwareSerialPort: String?

    init(
        eventLog: EventLog = EventLog(),
        agentInstaller: AgentInstaller = AgentInstaller(),
        preferences: VibeLightPreferences = VibeLightPreferences(),
        taskTracker: TaskTracker = TaskTracker(),
        firmwareFlashProcessRunner: FirmwareFlashProcessRunner = FirmwareFlashProcessRunner()
    ) {
        self.eventLog = eventLog
        self.agentInstaller = agentInstaller
        self.preferences = preferences
        self.taskTracker = taskTracker
        self.firmwareFlashProcessRunner = firmwareFlashProcessRunner
        self.autoConnectDevice = preferences.autoConnectDevice
        self.codex7dRedThresholdPercent = preferences.codex7dRedThresholdPercent
        self.selectedManualState = preferences.selectedManualState
        refreshManagedHookExecutable()
        refreshEvents()
        refreshAgentStatuses()
        bluetoothManager = BluetoothHardwareManager(
            onDevicesChanged: { [weak self] devices in
                guard let self else { return }
                hardwareDevices = devices
                if !firmwareOTADeviceCandidates.contains(where: { $0.id == selectedFirmwareOTADeviceID }) {
                    selectedFirmwareOTADeviceID = firmwareOTADeviceCandidates.first?.id
                }
            },
            onStateChanged: { [weak self] state, isScanning, message in
                self?.hardwareConnectionState = state
                self?.isHardwareScanning = isScanning
                self?.hardwareMessage = message
                self?.updateFirmwareReconnectMessage(for: state)
            },
            onHealthChanged: { [weak self] deviceID, health in
                guard let self else { return }
                if let health {
                    hardwareHealthPackets[deviceID] = health
                    hardwareHealthPacket = health
                    finishFirmwareReconnectIfNeeded(health: health)
                } else {
                    hardwareHealthPackets.removeValue(forKey: deviceID)
                    hardwareHealthPacket = hardwareHealthPackets.values.first
                }
            },
            onOTAProgress: { [weak self] progress in
                guard let self else { return }
                firmwareOTAProgress = progress
                guard let progress else { return }
                switch progress.stage {
                case .preparing:
                    firmwareFlashMessage = "正在建立安全的 BLE OTA 会话..."
                case .transferring:
                    firmwareFlashMessage = "无线传输中：\(progress.committedBytes) / \(progress.totalBytes) 字节。"
                case .verifying:
                    firmwareFlashMessage = "固件已传完，设备正在验证签名、SHA-256 和目标身份。"
                case .rebooting:
                    firmwareFlashMessage = "验证通过，设备正在重启并执行回滚确认。"
                case .complete:
                    firmwareFlashMessage = "无线更新完成，设备已运行 \(progress.targetVersion)。"
                case .failed(let message):
                    firmwareFlashMessage = "无线更新失败：\(message)"
                case .cancelled:
                    firmwareFlashMessage = "已取消无线更新，当前固件保持不变。"
                }
            },
            latestPacketData: { [weak self] maximumWriteLength in
                try? self?.latestPacket?.encodedJSON(maximumWriteLength: maximumWriteLength)
            },
            autoConnectEnabled: { [weak self] in
                self?.autoConnectDevice ?? false
            }
        )
        refreshFirmwareFlashing()
    }

    func refreshEvents() {
        do {
            let loadedEvents = try eventLog.readRecent(limit: 80)
            let latestCodexUsage = try eventLog.readLatestCodexUsage()
            events = loadedEvents

            let snapshot = taskTracker.snapshot(from: loadedEvents, fallbackCodexUsage: latestCodexUsage)
            let packet = snapshot.statusPacket(codex7dRedThresholdPercent: codex7dRedThresholdPercent)
            let packetData = try? packet.encodedJSON()

            displaySnapshot = snapshot
            currentState = snapshot.state
            self.latestPacket = packet
            latestPacketData = packetData
            bridgeMessage = bridgeMessage(for: snapshot, eventCount: loadedEvents.count)

            forwardLatestPacketToHardwareIfNeeded()
        } catch {
            bridgeMessage = "读取事件失败：\(error.localizedDescription)"
        }
    }

    func recordManualState() {
        let event = VibeHookEvent(
            source: .manual,
            kind: selectedManualState.manualEventKind,
            detail: selectedManualState.diagnosticDetail
        )
        do {
            try eventLog.append(event)
            refreshEvents()
        } catch {
            bridgeMessage = "写入手动状态失败：\(error.localizedDescription)"
        }
    }

    func refreshAgentStatuses() {
        for agent in AgentKind.allCases {
            do {
                agentStatuses[agent] = try agentInstaller.status(agent)
            } catch {
                agentStatuses[agent] = AgentInstallationStatus(
                    agent: agent,
                    isInstalled: false,
                    configURL: agentInstaller.primaryConfigURL(for: agent),
                    message: "读取失败：\(error.localizedDescription)"
                )
            }
        }
    }

    func installAgent(_ agent: AgentKind) {
        guard let hookURL = bundledHookURL() else {
            agentInstallMessage = "找不到 vibe-light-hook。请通过 ./script/build_and_run.sh 启动应用。"
            refreshAgentStatuses()
            return
        }

        do {
            let installedHookURL = try agentInstaller.prepareHookExecutable(from: hookURL)
            try agentInstaller.install(agent, hookExecutableURL: installedHookURL)
            agentInstallMessage = "\(agent.displayName) hook 已安装。"
        } catch {
            agentInstallMessage = "\(agent.displayName) 安装失败：\(error.localizedDescription)"
        }
        refreshAgentStatuses()
    }

    func uninstallAgent(_ agent: AgentKind) {
        do {
            try agentInstaller.uninstall(agent)
            agentInstallMessage = "\(agent.displayName) hook 已卸载。"
        } catch {
            agentInstallMessage = "\(agent.displayName) 卸载失败：\(error.localizedDescription)"
        }
        refreshAgentStatuses()
    }

    private func refreshManagedHookExecutable() {
        guard let hookURL = bundledHookURL() else {
            return
        }

        do {
            if try agentInstaller.refreshManagedHookExecutable(from: hookURL) {
                agentInstallMessage = "已更新 Vibe Light hook。"
            }
        } catch {
            agentInstallMessage = "更新 Vibe Light hook 失败：\(error.localizedDescription)"
        }
    }

    func startHardwareScan(clearDevices: Bool = false) {
        bluetoothManager?.startScan(clearDevices: clearDevices)
    }

    func restartHardwareScan(clearDevices: Bool = false) {
        bluetoothManager?.stopScan()
        bluetoothManager?.startScan(clearDevices: clearDevices)
    }

    func startHardwareAutoConnectIfNeeded() {
        guard autoConnectDevice, !didStartHardwareAutoConnect else {
            return
        }

        didStartHardwareAutoConnect = true
        DispatchQueue.main.async { [weak self] in
            self?.bluetoothManager?.startScan(autoConnectDevices: true)
        }
    }

    func stopHardwareScan() {
        bluetoothManager?.stopScan()
    }

    func connectHardwareDevice(_ device: HardwareDevice) {
        bluetoothManager?.connect(deviceID: device.id)
    }

    func disconnectHardwareDevice() {
        bluetoothManager?.disconnect()
    }

    func sendLatestPacketToHardware() {
        if bluetoothManager?.sendLatestPacket() == true {
            lastForwardedPacketData = latestPacketData
        }
    }

    func sendHardwareDemoPacket(_ scenario: HardwareDemoPacketScenario) {
        if bluetoothManager?.sendPacket(scenario.packet()) == true {
            demoPacketHold.start()
            lastForwardedPacketData = nil
        }
    }

    func refreshHardwareHealth() {
        bluetoothManager?.readHealthPacket()
    }

    func startFirmwareOTA() {
        guard !isFirmwareOTAUpdating, !isFirmwareChipProbing, !isFirmwareFlashing else { return }
        guard let bundle = firmwareBundle,
              let metadata = bundle.manifest.ota,
              let applicationURL = bundle.otaApplicationURL else {
            firmwareFlashMessage = "当前固件包不包含可无线更新的 application 镜像。"
            return
        }
        guard let deviceID = selectedFirmwareOTADeviceID,
              firmwareOTADeviceCandidates.contains(where: { $0.id == deviceID }) else {
            firmwareFlashMessage = "请先选择一个已连接的目标设备。"
            return
        }
        switch FirmwareOTAEligibility.evaluate(
            protocolVersion: metadata.protocolVersion,
            secureSigned: metadata.secureSigned,
            bundleProjectName: metadata.projectName,
            health: hardwareHealthPackets[deviceID]
        ) {
        case .ready:
            break
        case .unsupportedProtocol:
            firmwareFlashMessage = "当前 App 不支持固件包的 OTA 协议版本。"
            return
        case .unsignedBundle:
            firmwareFlashMessage = "此固件没有安全签名，只能通过 USB 烧录。"
            return
        case .usbInitializationRequired:
            firmwareFlashMessage = "目标设备尚未完成一次性 USB OTA 初始化。"
            return
        case .signedInitializationRequired:
            firmwareFlashMessage = "目标设备未强制验证签名更新，请先通过 USB 写入 signed A/B 固件。"
            return
        case .wrongProject:
            firmwareFlashMessage = "所选固件与目标设备不匹配。"
            return
        }
        guard bluetoothManager?.canStartFirmwareOTA(deviceID: deviceID) == true else {
            firmwareFlashMessage = "目标设备的 OTA 服务尚未就绪，请刷新健康状态后重试。"
            return
        }

        var sessionID = UInt32.random(in: 1 ... UInt32.max)
        if sessionID == 0 { sessionID = 1 }
        bluetoothManager?.startFirmwareOTA(FirmwareOTARequest(
            deviceID: deviceID,
            applicationURL: applicationURL,
            sessionID: sessionID,
            imageSize: metadata.size,
            projectName: metadata.projectName,
            appVersion: metadata.appVersion,
            sha256: metadata.sha256
        ))
    }

    func cancelFirmwareOTA() {
        bluetoothManager?.cancelFirmwareOTA()
    }

    func openBluetoothPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshFirmwareFlashing() {
        firmwareSerialPorts = FirmwareSerialPortDiscovery().candidatePorts()
        if selectedFirmwareSerialPort == nil || firmwareSerialPorts.contains(selectedFirmwareSerialPort ?? "") == false {
            selectedFirmwareSerialPort = firmwareSerialPorts.first
        }
        clearFirmwareChipProbeConfirmation()
        firmwareFlashFailureKind = nil

        do {
            let bundles = try bundledFirmwareBundles()
            guard !bundles.isEmpty else {
                firmwareBundles = []
                firmwareBundle = nil
                firmwareFlashMessage = "当前 App 未内置固件包。发布构建前请先生成 FirmwareBundles。"
                return
            }
            firmwareBundles = bundles
            let selectedHardware = bundles.contains { $0.manifest.targetHardware == selectedFirmwareHardware }
                ? selectedFirmwareHardware
                : bundles.first?.manifest.targetHardware
            selectedFirmwareHardware = selectedHardware
            let bundle = bundles.first { $0.manifest.targetHardware == selectedHardware } ?? bundles[0]
            firmwareBundle = bundle
            firmwareFlashMessage = "已加载固件 \(bundle.manifest.version) / \(bundle.manifest.targetHardware)。"
        } catch {
            firmwareBundles = []
            firmwareBundle = nil
            firmwareFlashMessage = "固件包不可用：\(error.localizedDescription)"
        }
    }

    func startNewFirmwareFlash() {
        guard !isFirmwareChipProbing, !isFirmwareFlashing, !isFirmwareOTAUpdating else {
            return
        }

        didCompleteFirmwareFlash = false
        isFirmwareAwaitingReconnect = false
        firmwareFlashFailureKind = nil
        firmwareFlashLog = ""
        firmwareFlashProgress = nil
        refreshFirmwareFlashing()
    }

    func probeFirmwareChip() {
        guard !isFirmwareChipProbing, !isFirmwareFlashing, !isFirmwareOTAUpdating else {
            return
        }
        guard let firmwareBundle else {
            firmwareFlashMessage = "没有可烧录的固件包。"
            return
        }
        guard let selectedFirmwareSerialPort else {
            firmwareFlashMessage = "未发现 USB 串口。请连接 ESP32-S3 后刷新。"
            return
        }
        guard let helperURL = firmwareFlashHelperURL() else {
            firmwareFlashMessage = "找不到烧录 helper。发布包需要内置 FirmwareTools/vibe-light-firmware-flasher。"
            return
        }

        let command = FirmwareChipProbeCommand(targetChip: firmwareBundle.manifest.targetChip, port: selectedFirmwareSerialPort)
        clearFirmwareChipProbeConfirmation()
        firmwareFlashFailureKind = nil
        isFirmwareChipProbing = true
        firmwareFlashMessage = "正在读取 \(selectedFirmwareSerialPort) 的芯片信息..."
        firmwareFlashLog = ""
        firmwareFlashProgress = nil

        Task { [helperURL, command, selectedFirmwareSerialPort] in
            let logStream = makeFirmwareFlashLogStream()
            do {
                let output = try await runFirmwareTool(
                    helperURL: helperURL,
                    arguments: command.esptoolArguments,
                    onOutput: logStream.append
                )
                await drainFirmwareFlashLogStream(logStream)
                let result = try FirmwareChipProbeResult.parse(output: output)
                firmwareFlashLog = output
                firmwareFlashProgress = FirmwareFlashProgressSnapshot.parse(output: output)
                if result.matches(targetChip: command.targetChip) {
                    firmwareChipProbeResult = result
                    confirmedFirmwareSerialPort = selectedFirmwareSerialPort
                    firmwareFlashFailureKind = nil
                    firmwareFlashMessage = firmwareChipProbeMessage(for: result)
                } else {
                    firmwareFlashFailureKind = .unsupportedChip
                    firmwareFlashMessage = "芯片确认失败：读取到 \(result.chipName)，目标固件需要 \(command.targetChip)。"
                }
                isFirmwareChipProbing = false
            } catch {
                await drainFirmwareFlashLogStream(logStream)
                firmwareFlashLog = (error as? FirmwareFlashProcessError)?.output ?? firmwareFlashLog
                firmwareFlashProgress = FirmwareFlashProgressSnapshot.parse(output: firmwareFlashLog)
                let advice = FirmwareFlashFailureAdvice(error: error)
                firmwareFlashFailureKind = advice.kind
                firmwareFlashMessage = advice.message
                isFirmwareChipProbing = false
                clearFirmwareChipProbeConfirmation()
            }
        }
    }

    func flashFirmware() {
        guard !isFirmwareFlashing, !isFirmwareOTAUpdating else {
            return
        }
        guard let firmwareBundle else {
            firmwareFlashMessage = "没有可烧录的固件包。"
            return
        }
        guard let selectedFirmwareSerialPort else {
            firmwareFlashMessage = "未发现 USB 串口。请连接 ESP32-S3 后刷新。"
            return
        }
        guard firmwareChipProbeResult != nil, confirmedFirmwareSerialPort == selectedFirmwareSerialPort else {
            firmwareFlashMessage = "烧录前请先读取并确认芯片。"
            return
        }
        guard let helperURL = firmwareFlashHelperURL() else {
            firmwareFlashMessage = "找不到烧录 helper。发布包需要内置 FirmwareTools/vibe-light-firmware-flasher。"
            return
        }

        let command = FirmwareFlashCommand(bundle: firmwareBundle, port: selectedFirmwareSerialPort)
        isFirmwareFlashing = true
        didCompleteFirmwareFlash = false
        firmwareFlashFailureKind = nil
        hardwareHealthPacket = nil
        hardwareHealthPackets.removeAll()
        isFirmwareAwaitingReconnect = false
        firmwareFlashMessage = "正在烧录 \(selectedFirmwareSerialPort)..."
        firmwareFlashLog = ""
        firmwareFlashProgress = nil

        Task { [helperURL, command] in
            let logStream = makeFirmwareFlashLogStream()
            do {
                let output = try await runFirmwareFlash(
                    helperURL: helperURL,
                    command: command,
                    onOutput: logStream.append
                )
                await drainFirmwareFlashLogStream(logStream)
                firmwareFlashLog = output
                firmwareFlashProgress = FirmwareFlashProgressSnapshot.parse(output: output)
                didCompleteFirmwareFlash = true
                isFirmwareAwaitingReconnect = true
                firmwareFlashFailureKind = nil
                firmwareFlashMessage = "烧录完成。请点按 RST 正常启动设备，App 会继续扫描 \(selectedFirmwareBLEDeviceName)。"
                isFirmwareFlashing = false
                startHardwareScan(clearDevices: true)
            } catch {
                await drainFirmwareFlashLogStream(logStream)
                firmwareFlashLog = (error as? FirmwareFlashProcessError)?.output ?? firmwareFlashLog
                firmwareFlashProgress = FirmwareFlashProgressSnapshot.parse(output: firmwareFlashLog)
                let advice = FirmwareFlashFailureAdvice(error: error)
                firmwareFlashFailureKind = advice.kind
                firmwareFlashMessage = advice.message
                isFirmwareFlashing = false
                isFirmwareAwaitingReconnect = false
            }
        }
    }

    private func clearFirmwareChipProbeConfirmation() {
        firmwareChipProbeResult = nil
        confirmedFirmwareSerialPort = nil
    }

    private func appendFirmwareFlashLog(_ chunk: String) {
        firmwareFlashLog.append(chunk)
        firmwareFlashProgress = FirmwareFlashProgressSnapshot.parse(output: firmwareFlashLog)
    }

    private func makeFirmwareFlashLogStream() -> FirmwareFlashLogStream {
        let group = DispatchGroup()
        let append: @Sendable (String) -> Void = { [weak self] chunk in
            group.enter()
            DispatchQueue.main.async {
                self?.appendFirmwareFlashLog(chunk)
                group.leave()
            }
        }
        return FirmwareFlashLogStream(group: group, append: append)
    }

    private func drainFirmwareFlashLogStream(_ stream: FirmwareFlashLogStream) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                stream.group.wait()
                continuation.resume()
            }
        }
    }

    private func firmwareChipProbeMessage(for result: FirmwareChipProbeResult) -> String {
        if let macAddress = result.macAddress {
            return "已确认 \(result.chipName)，MAC \(macAddress)。可继续烧录。"
        }
        return "已确认 \(result.chipName)。可继续烧录。"
    }

    private func updateFirmwareReconnectMessage(for state: HardwareConnectionState) {
        guard isFirmwareAwaitingReconnect else {
            return
        }
        if state.isConnected {
            firmwareFlashMessage = "烧录完成。已有 Vibe Light 设备在线，仍在等待 \(selectedFirmwareBLEDeviceName) 的健康状态。"
        }
    }

    private func finishFirmwareReconnectIfNeeded(health: HealthPacket?) {
        guard isFirmwareAwaitingReconnect,
              let health,
              health.device == selectedFirmwareBLEDeviceName else {
            return
        }
        firmwareFlashMessage = "烧录完成。已重新连接 \(health.device)，健康状态已更新。"
        isFirmwareAwaitingReconnect = false
    }

    func pollEvents() async {
        while !Task.isCancelled {
            refreshEvents()
            try? await Task.sleep(for: .milliseconds(1_500))
        }
    }

    private func bundledHookURL() -> URL? {
        guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            return nil
        }

        let url = executableDirectory.appendingPathComponent("vibe-light-hook")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func bundledFirmwareBundles() throws -> [FirmwareBundle] {
        if let catalogURL = AppResourceBundle.bundle.url(forResource: "FirmwareBundles", withExtension: nil) {
            let bundles = try FirmwareBundleCatalog().validatedBundles(in: catalogURL)
            if !bundles.isEmpty {
                return bundles
            }
        }
        if let legacyURL = AppResourceBundle.bundle.url(forResource: "FirmwareBundle", withExtension: nil),
           FileManager.default.fileExists(atPath: legacyURL.appendingPathComponent("manifest.json").path) {
            return [try FirmwareBundleValidator().validatedBundle(at: legacyURL)]
        }
        return []
    }

    private func firmwareFlashHelperURL() -> URL? {
        if let bundledURL = AppResourceBundle.bundle.url(forResource: "FirmwareTools/vibe-light-firmware-flasher", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundledURL.path) {
            return bundledURL
        }

        let developerCandidates = [
            "/opt/homebrew/bin/esptool.py",
            "/usr/local/bin/esptool.py",
            "/opt/homebrew/bin/esptool",
            "/usr/local/bin/esptool",
        ].map(URL.init(fileURLWithPath:))

        return developerCandidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func runFirmwareFlash(
        helperURL: URL,
        command: FirmwareFlashCommand,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await runFirmwareTool(helperURL: helperURL, arguments: command.esptoolArguments, onOutput: onOutput)
    }

    private func runFirmwareTool(
        helperURL: URL,
        arguments: [String],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        try await firmwareFlashProcessRunner.run(
            executableURL: helperURL,
            arguments: arguments,
            onOutput: onOutput
        )
    }

    private func forwardLatestPacketToHardwareIfNeeded() {
        guard let latestPacketData,
              bluetoothManager?.canWriteStatus == true,
              demoPacketHold.allowsLatestPacketForward(),
              latestPacketData != lastForwardedPacketData else {
            return
        }

        if bluetoothManager?.sendLatestPacket() == true {
            lastForwardedPacketData = latestPacketData
        }
    }

    private func bridgeMessage(for snapshot: DisplaySnapshot, eventCount: Int) -> String {
        let taskCount = snapshot.tasks.count
        guard eventCount > 0 else {
            return "等待 hook 事件..."
        }

        return "聚合状态：\(snapshot.state.title) / \(taskCount) 个任务"
    }
}

private struct FirmwareFlashLogStream: @unchecked Sendable {
    let group: DispatchGroup
    let append: @Sendable (String) -> Void
}

enum AppTab: String, CaseIterable, Identifiable {
    case general
    case agents
    case hardware
    case firmware
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .agents: "智能体安装"
        case .hardware: "硬件设备"
        case .firmware: "固件烧录"
        case .events: "事件"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .agents: "terminal"
        case .hardware: "dot.radiowaves.left.and.right"
        case .firmware: "memorychip"
        case .events: "waveform.path.ecg"
        }
    }
}

private extension DisplayState {
    var manualEventKind: HookEventKind {
        switch self {
        case .idle: .sessionEnd
        case .busy: .preToolUse
        case .waiting: .permissionRequest
        case .success: .stop
        case .error: .stopFailure
        case .offline: .permissionDenied
        }
    }
}
