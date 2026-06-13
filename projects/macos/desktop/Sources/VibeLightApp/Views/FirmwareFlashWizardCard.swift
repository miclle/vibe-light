import SwiftUI
import VibeLightCore

struct FirmwareFlashWizardCard: View {
    @ObservedObject var model: VibeLightAppModel
    @State private var showsDetailedLog = true

    private let logBottomID = "firmware-flash-log-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            wizardHeader

            HStack(alignment: .top, spacing: 22) {
                stepRail
                    .frame(width: 260, alignment: .topLeading)

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    activeStepPanel

                    firmwareLogPanel
                }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var wizardHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("固件烧录向导")
                .font(.title2.bold())

            if let bundle = model.firmwareBundle {
                HStack(spacing: 16) {
                    FirmwareMetadataItem(title: "固件版本", value: bundle.manifest.version)
                    FirmwareMetadataItem(title: "目标芯片", value: bundle.manifest.targetChip)
                    FirmwareMetadataItem(title: "Flash", value: bundle.manifest.flashSize)
                }
            } else {
                Text(model.firmwareSerialPorts.isEmpty ? "连接 USB 后刷新串口" : "等待可用固件包")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(FirmwareWizardStep.allCases) { step in
                FirmwareWizardStepRow(
                    step: step,
                    status: status(for: step),
                    isLast: step == FirmwareWizardStep.allCases.last
                )
            }
        }
    }

    @ViewBuilder
    private var firmwareLogPanel: some View {
        if shouldShowFirmwareLog {
            DisclosureGroup(isExpanded: $showsDetailedLog) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(firmwareLogText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(model.firmwareFlashLog.isEmpty ? .tertiary : .secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)

                        Color.clear
                            .frame(height: 1)
                            .id(logBottomID)
                    }
                    .frame(minHeight: 120, maxHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65))
                    )
                    .onAppear {
                        proxy.scrollTo(logBottomID, anchor: .bottom)
                    }
                    .onChange(of: model.firmwareFlashLog) {
                        showsDetailedLog = true
                        DispatchQueue.main.async {
                            proxy.scrollTo(logBottomID, anchor: .bottom)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(spacing: 8) {
                    Label("烧录日志", systemImage: "doc.text.magnifyingglass")
                        .font(.callout.weight(.semibold))
                    if model.isFirmwareChipProbing || model.isFirmwareFlashing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text("实时输出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var activeStepPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: activeStep.systemImage)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeStep.title)
                        .font(.title3.bold())
                    Text(activeStep.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isFirmwareChipProbing || model.isFirmwareFlashing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(model.firmwareFlashMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            switch activeStep {
            case .connectUSB:
                connectUSBPanel
            case .readChip:
                readChipPanel
            case .enterDownloadMode:
                enterDownloadModePanel
            case .confirmAndFlash:
                confirmAndFlashPanel
            case .writeFirmware:
                writeFirmwarePanel
            case .restartDevice:
                restartDevicePanel
            case .connectBLE:
                connectBLEPanel
            case .finish:
                finishPanel
            }
        }
    }

    private var connectUSBPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("用 USB 数据线连接 Waveshare ESP32-S3-LCD-3.16，然后刷新串口。")
                .font(.callout)

            firmwarePortControls

            if model.firmwareSerialPorts.isEmpty {
                Label("未发现可用串口。请确认使用的是数据线，设备已通电。", systemImage: "cable.connector.slash")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readChipPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            firmwarePortControls

            Button {
                model.probeFirmwareChip()
            } label: {
                Label(model.isFirmwareChipProbing ? "读取中" : "读取芯片", systemImage: "checkmark.shield")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isFirmwareFlashing || model.isFirmwareChipProbing || model.firmwareBundle == nil || model.selectedFirmwareSerialPort == nil)

            Text("这一步只读取芯片型号和 MAC，不写入 flash。确认是 ESP32-S3 后才会启用烧录。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var enterDownloadModePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                InstructionLine(index: 1, text: "按住 BOOT 不松开。")
                InstructionLine(index: 2, text: "点按一下 RST。")
                InstructionLine(index: 3, text: "继续按住 BOOT 约 1 秒。")
                InstructionLine(index: 4, text: "松开 BOOT，然后重新读取芯片。")
            }

            Button {
                model.probeFirmwareChip()
            } label: {
                Label(model.isFirmwareChipProbing ? "重新读取中" : "我已完成，重新读取", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isFirmwareFlashing || model.isFirmwareChipProbing || model.firmwareBundle == nil || model.selectedFirmwareSerialPort == nil)
        }
    }

    private var confirmAndFlashPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let chipProbeResult = model.firmwareChipProbeResult {
                Label(firmwareChipProbeSummary(chipProbeResult), systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            }

            if let bundle = model.firmwareBundle {
                VStack(alignment: .leading, spacing: 6) {
                    FirmwareFactRow(title: "固件版本", value: bundle.manifest.version)
                    FirmwareFactRow(title: "目标硬件", value: bundle.manifest.targetHardware)
                    FirmwareFactRow(title: "Flash", value: "\(bundle.manifest.flashMode) / \(bundle.manifest.flashFreq) / \(bundle.manifest.flashSize)")
                }
            }

            Button {
                model.flashFirmware()
            } label: {
                Label("烧录固件", systemImage: "bolt.horizontal.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isFirmwareFlashing || model.isFirmwareChipProbing || model.firmwareBundle == nil || model.selectedFirmwareSerialPort == nil || model.firmwareChipProbeResult == nil)
        }
    }

    private var writeFirmwarePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("正在写入 bootloader、partition table 和 app 分区。", systemImage: "square.and.arrow.down")
            Label("写入和校验期间不要拔掉 USB，也不要按 RST。", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .font(.callout)
    }

    private var restartDevicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                InstructionLine(index: 1, text: "点按一下 RST，让设备正常启动。")
                InstructionLine(index: 2, text: "这一步不要按住 BOOT。")
                InstructionLine(index: 3, text: "如果屏幕没有画面，再点按一次 RST。")
            }

            Button {
                model.restartHardwareScan(clearDevices: true)
            } label: {
                Label("我已按 RST，重新扫描", systemImage: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectBLEPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hardwareConnectionState.isConnected {
                Label("已连接 VibeLight-S3，正在读取健康状态。", systemImage: "link")
                    .foregroundStyle(.green)

                Button {
                    model.refreshHardwareHealth()
                } label: {
                    Label("读取健康状态", systemImage: "heart.text.square")
                }
                .buttonStyle(.borderedProminent)
            } else if model.hardwareDevices.isEmpty {
                Label("等待发现 VibeLight-S3。设备屏幕亮起后，通常几秒内会出现。", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)

                Button {
                    model.restartHardwareScan()
                } label: {
                    Label(model.isHardwareScanning ? "重新扫描" : "继续扫描", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择刚启动的 VibeLight-S3。")
                        .font(.callout)
                    ForEach(model.hardwareDevices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(signalTint(for: device.rssi))
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.headline)
                                Text("\(signalStrengthLabel(for: device.rssi)) · \(device.rssi) dBm 实时更新")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                model.connectHardwareDevice(device)
                            } label: {
                                Label("连接", systemImage: "link")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.hardwareConnectionState.isConnecting)
                        }
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55))
                        )
                    }
                }
            }
        }
    }

    private var finishPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("烧录完成，设备已重新连接。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            if let health = model.hardwareHealthPacket {
                VStack(alignment: .leading, spacing: 6) {
                    FirmwareFactRow(title: "设备", value: health.device)
                    FirmwareFactRow(title: "最近状态", value: health.lastState.title)
                    FirmwareFactRow(title: "背光", value: health.backlightOn.map { $0 ? "开启" : "关闭" } ?? "未知")
                }
            }

            HStack(spacing: 10) {
                Button {
                    model.startNewFirmwareFlash()
                } label: {
                    Label("开始新的烧录", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    model.refreshHardwareHealth()
                } label: {
                    Label("刷新健康状态", systemImage: "heart.text.square")
                }
                .buttonStyle(.bordered)
                .disabled(!model.hardwareConnectionState.isConnected)
            }
        }
    }

    private var firmwarePortControls: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("USB 串口", selection: $model.selectedFirmwareSerialPort) {
                if model.firmwareSerialPorts.isEmpty {
                    Text("未发现串口").tag(String?.none)
                } else {
                    ForEach(model.firmwareSerialPorts, id: \.self) { port in
                        Text(port).tag(Optional(port))
                    }
                }
            }
            .frame(minWidth: 280, maxWidth: 420)
            .disabled(model.isFirmwareFlashing || model.isFirmwareChipProbing)

            Button {
                model.refreshFirmwareFlashing()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.isFirmwareFlashing || model.isFirmwareChipProbing)
        }
    }

    private var activeStep: FirmwareWizardStep {
        if model.didCompleteFirmwareFlash, model.hardwareHealthPacket != nil, !model.isFirmwareAwaitingReconnect {
            return .finish
        }
        if model.isFirmwareFlashing {
            return .writeFirmware
        }
        if model.isFirmwareAwaitingReconnect {
            if model.hardwareConnectionState.isConnected || !model.hardwareDevices.isEmpty {
                return .connectBLE
            }
            return .restartDevice
        }
        if model.firmwareChipProbeResult != nil {
            return .confirmAndFlash
        }
        if model.firmwareFlashFailureKind == .downloadMode {
            return .enterDownloadMode
        }
        if model.firmwareBundle != nil, model.selectedFirmwareSerialPort != nil {
            return .readChip
        }
        return .connectUSB
    }

    private func status(for step: FirmwareWizardStep) -> FirmwareWizardStepStatus {
        if step == activeStep {
            return .active
        }
        if step.rawValue < activeStep.rawValue {
            return .complete
        }
        return .pending
    }

    private var shouldShowFirmwareLog: Bool {
        !model.firmwareFlashLog.isEmpty || model.isFirmwareChipProbing || model.isFirmwareFlashing
    }

    private var firmwareLogText: String {
        if model.firmwareFlashLog.isEmpty {
            return "等待烧录程序输出..."
        }
        return model.firmwareFlashLog
    }

    private func firmwareChipProbeSummary(_ result: FirmwareChipProbeResult) -> String {
        if let macAddress = result.macAddress {
            return "已确认 \(result.chipName) / \(macAddress)"
        }
        return "已确认 \(result.chipName)"
    }

    private func signalStrengthLabel(for rssi: Int) -> String {
        switch rssi {
        case (-55)...:
            return "信号很强"
        case -70 ..< -55:
            return "信号良好"
        default:
            return "信号较弱"
        }
    }

    private func signalTint(for rssi: Int) -> Color {
        switch rssi {
        case (-60)...:
            return .green
        case -78 ..< -60:
            return .orange
        default:
            return .red
        }
    }
}

private enum FirmwareWizardStep: Int, CaseIterable, Identifiable {
    case connectUSB
    case readChip
    case enterDownloadMode
    case confirmAndFlash
    case writeFirmware
    case restartDevice
    case connectBLE
    case finish

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .connectUSB: "连接 USB"
        case .readChip: "读取芯片"
        case .enterDownloadMode: "进入下载模式"
        case .confirmAndFlash: "确认并烧录"
        case .writeFirmware: "写入固件"
        case .restartDevice: "重启设备"
        case .connectBLE: "连接 VibeLight"
        case .finish: "完成"
        }
    }

    var summary: String {
        switch self {
        case .connectUSB: "先让 macOS 看到 ESP32-S3 串口。"
        case .readChip: "确认芯片型号和 MAC。"
        case .enterDownloadMode: "按 BOOT/RST 后重新读取。"
        case .confirmAndFlash: "确认目标后才开始写入。"
        case .writeFirmware: "等待写入和 hash 校验完成。"
        case .restartDevice: "烧录后用 RST 正常启动。"
        case .connectBLE: "等待发现并连接 VibeLight-S3。"
        case .finish: "健康状态已更新。"
        }
    }

    var systemImage: String {
        switch self {
        case .connectUSB: "cable.connector"
        case .readChip: "checkmark.shield"
        case .enterDownloadMode: "button.programmable"
        case .confirmAndFlash: "bolt.horizontal.circle"
        case .writeFirmware: "square.and.arrow.down"
        case .restartDevice: "restart.circle"
        case .connectBLE: "dot.radiowaves.left.and.right"
        case .finish: "checkmark.circle"
        }
    }
}

private enum FirmwareWizardStepStatus {
    case complete
    case active
    case pending

    var icon: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .active: "record.circle"
        case .pending: "circle"
        }
    }

    var tint: Color {
        switch self {
        case .complete: .green
        case .active: .blue
        case .pending: .secondary
        }
    }
}

private struct FirmwareWizardStepRow: View {
    var step: FirmwareWizardStep
    var status: FirmwareWizardStepStatus
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.tint)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 20)
                if !isLast {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.55))
                        .frame(width: 1, height: 30)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(status == .active ? .callout.bold() : .callout)
                    .foregroundStyle(status == .pending ? .secondary : .primary)
                Text(step.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.bottom, isLast ? 0 : 4)
    }
}

private struct InstructionLine: View {
    var index: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
        }
    }
}

private struct FirmwareFactRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct FirmwareMetadataItem: View {
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}
