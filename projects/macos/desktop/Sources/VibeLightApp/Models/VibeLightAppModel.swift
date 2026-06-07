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
    private var bluetoothManager: BluetoothHardwareManager?
    private var latestPacketData: Data?
    private var lastForwardedPacketData: Data?
    private var didStartHardwareAutoConnect = false

    init(
        eventLog: EventLog = EventLog(),
        agentInstaller: AgentInstaller = AgentInstaller(),
        preferences: VibeLightPreferences = VibeLightPreferences(),
        taskTracker: TaskTracker = TaskTracker()
    ) {
        self.eventLog = eventLog
        self.agentInstaller = agentInstaller
        self.preferences = preferences
        self.taskTracker = taskTracker
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
    }

    func refreshEvents() {
        do {
            let loadedEvents = try eventLog.readRecent(limit: 80)
            events = loadedEvents

            let snapshot = taskTracker.snapshot(from: loadedEvents)
            let packet = snapshot.statusPacket
            let packetData = try? packet.encodedJSON()
            let packetChanged = packetData != latestPacketData

            displaySnapshot = snapshot
            currentState = snapshot.state
            self.latestPacket = packet
            latestPacketData = packetData
            bridgeMessage = bridgeMessage(for: snapshot, eventCount: loadedEvents.count)

            if packetChanged {
                forwardLatestPacketToHardwareIfNeeded()
            }
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
        _ = bluetoothManager?.sendPacket(scenario.packet())
    }

    func refreshHardwareHealth() {
        bluetoothManager?.readHealthPacket()
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

    private func forwardLatestPacketToHardwareIfNeeded() {
        guard let latestPacketData,
              bluetoothManager?.canWriteStatus == true,
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
