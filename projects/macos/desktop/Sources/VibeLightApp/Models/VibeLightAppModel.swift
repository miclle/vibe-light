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
    @Published private(set) var hardwareMessage = "未扫描设备。"
    @Published private(set) var isHardwareScanning = false
    @Published private(set) var firmwareSerialPorts: [String] = []
    @Published private(set) var firmwareBundle: FirmwareBundle?
    @Published private(set) var firmwareFlashMessage = "未检查固件包。"
    @Published private(set) var firmwareFlashLog = ""
    @Published private(set) var isFirmwareFlashing = false
    @Published var selectedFirmwareSerialPort: String?
    @Published var launchAtLogin = false
    @Published var autoConnectDevice: Bool {
        didSet {
            preferences.autoConnectDevice = autoConnectDevice
        }
    }
    @Published var selectedManualState: DisplayState {
        didSet {
            preferences.selectedManualState = selectedManualState
        }
    }
    @Published var bridgeMessage = "等待 hook 事件..."

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
        self.selectedManualState = preferences.selectedManualState
        refreshEvents()
        refreshAgentStatuses()
        bluetoothManager = BluetoothHardwareManager(
            onDevicesChanged: { [weak self] devices in
                self?.hardwareDevices = devices
            },
            onStateChanged: { [weak self] state, isScanning, message in
                self?.hardwareConnectionState = state
                self?.isHardwareScanning = isScanning
                self?.hardwareMessage = message
            },
            onHealthChanged: { [weak self] health in
                self?.hardwareHealthPacket = health
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
            events = loadedEvents

            let snapshot = taskTracker.snapshot(from: loadedEvents)
            let packet = snapshot.statusPacket
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

    func startHardwareScan() {
        bluetoothManager?.startScan()
    }

    func startHardwareAutoConnectIfNeeded() {
        guard autoConnectDevice, !didStartHardwareAutoConnect else {
            return
        }

        didStartHardwareAutoConnect = true
        DispatchQueue.main.async { [weak self] in
            self?.bluetoothManager?.startScan(autoConnectFirstDevice: true)
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

        do {
            guard let bundleURL = bundledFirmwareURL() else {
                firmwareBundle = nil
                firmwareFlashMessage = "当前 App 未内置固件包。发布构建前请先生成 FirmwareBundle。"
                return
            }

            let bundle = try FirmwareBundleValidator().validatedBundle(at: bundleURL)
            firmwareBundle = bundle
            firmwareFlashMessage = "已加载固件 \(bundle.manifest.version) / \(bundle.manifest.targetHardware)。"
        } catch {
            firmwareBundle = nil
            firmwareFlashMessage = "固件包不可用：\(error.localizedDescription)"
        }
    }

    func flashFirmware() {
        guard !isFirmwareFlashing else {
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

        let command = FirmwareFlashCommand(bundle: firmwareBundle, port: selectedFirmwareSerialPort)
        isFirmwareFlashing = true
        firmwareFlashMessage = "正在烧录 \(selectedFirmwareSerialPort)..."
        firmwareFlashLog = ""

        Task { [helperURL, command] in
            do {
                let output = try await runFirmwareFlash(helperURL: helperURL, command: command)
                firmwareFlashLog = output
                firmwareFlashMessage = "烧录完成。正在扫描 VibeLight-S3..."
                isFirmwareFlashing = false
                startHardwareScan()
            } catch {
                firmwareFlashLog = (error as? FirmwareFlashProcessError)?.output ?? firmwareFlashLog
                firmwareFlashMessage = FirmwareFlashFailureAdvice(error: error).message
                isFirmwareFlashing = false
            }
        }
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

    private func bundledFirmwareURL() -> URL? {
        guard let url = AppResourceBundle.bundle.url(forResource: "FirmwareBundle", withExtension: nil),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else {
            return nil
        }
        return url
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

    private func runFirmwareFlash(helperURL: URL, command: FirmwareFlashCommand) async throws -> String {
        try await firmwareFlashProcessRunner.run(
            executableURL: helperURL,
            arguments: command.esptoolArguments
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

enum AppTab: String, CaseIterable, Identifiable {
    case general
    case agents
    case hardware
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .agents: "智能体安装"
        case .hardware: "硬件设备"
        case .events: "事件"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .agents: "terminal"
        case .hardware: "dot.radiowaves.left.and.right"
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
