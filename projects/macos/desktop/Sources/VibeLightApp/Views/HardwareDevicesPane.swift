import SwiftUI
import VibeLightCore

struct HardwareDevicesPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                connectionHeader

                HStack(alignment: .top, spacing: 18) {
                    deviceDiscoveryCard
                        .frame(minWidth: 360, maxWidth: .infinity, alignment: .top)
                    healthCard
                        .frame(minWidth: 300, maxWidth: 420, alignment: .top)
                }

                demoPacketsCard
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle("硬件设备")
    }

    private var connectionHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(connectionTint.opacity(0.13))
                    Image(systemName: connectionIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(connectionTint)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(model.hardwareConnectionState.title)
                            .font(.title2.bold())
                        if model.isHardwareScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(model.hardwareMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    model.startHardwareScan()
                } label: {
                    Label(model.isHardwareScanning ? "扫描中" : "扫描设备", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isHardwareScanning)

                Button {
                    model.stopHardwareScan()
                } label: {
                    Label("停止", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .disabled(!model.isHardwareScanning)
            }

            HStack(spacing: 10) {
                Button {
                    model.disconnectHardwareDevice()
                } label: {
                    Label("断开连接", systemImage: "xmark.circle")
                }
                .disabled(!model.hardwareConnectionState.isConnected)

                Button {
                    model.sendLatestPacketToHardware()
                } label: {
                    Label("发送当前状态", systemImage: "paperplane")
                }
                .disabled(!model.hardwareConnectionState.isConnected)

                Button {
                    model.refreshHardwareHealth()
                } label: {
                    Label("读取健康状态", systemImage: "heart.text.square")
                }
                .disabled(!model.hardwareConnectionState.isConnected)

                if model.hardwareMessage.contains("蓝牙权限") {
                    Button {
                        model.openBluetoothPrivacySettings()
                    } label: {
                        Label("打开蓝牙权限设置", systemImage: "lock.shield")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
        )
    }

    private var deviceDiscoveryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(
                title: "发现设备",
                subtitle: model.hardwareDevices.isEmpty ? "等待广播 VibeLight 服务的 ESP32-S3" : "\(model.hardwareDevices.count) 台可用设备",
                systemImage: "antenna.radiowaves.left.and.right"
            )

            if model.hardwareDevices.isEmpty {
                ContentUnavailableView(
                    "未发现设备",
                    systemImage: "cpu",
                    description: Text("点击扫描设备，查找附近的 VibeLight-S3。")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.hardwareDevices) { device in
                        HardwareDeviceRow(
                            device: device,
                            connectionState: model.hardwareConnectionState
                        ) {
                            model.connectHardwareDevice(device)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(
                title: "设备健康",
                subtitle: model.hardwareHealthPacket == nil ? "连接后读取运行状态" : "最近一次健康状态",
                systemImage: "heart.text.square"
            )

            if let health = model.hardwareHealthPacket {
                VStack(spacing: 0) {
                    HealthMetricRow(title: "设备", value: health.device, systemImage: "display")
                    HealthMetricRow(title: "运行时间", value: formatUptime(health.uptimeMs), systemImage: "timer")
                    HealthMetricRow(title: "连接", value: health.connected ? "已连接" : "未连接", systemImage: "link")
                    HealthMetricRow(title: "最近状态", value: health.lastState.title, systemImage: "waveform.path.ecg")
                }
            } else {
                ContentUnavailableView(
                    "暂无健康状态",
                    systemImage: "heart.text.square",
                    description: Text("连接设备后点击读取健康状态。")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var demoPacketsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(
                title: "演示包",
                subtitle: "向已连接硬件发送常用状态样例",
                systemImage: "sparkles"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(HardwareDemoPacketScenario.allCases) { scenario in
                    Button {
                        model.sendHardwareDemoPacket(scenario)
                    } label: {
                        Label(scenario.title, systemImage: icon(for: scenario))
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.hardwareConnectionState.isConnected)
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatUptime(_ uptimeMs: Int64) -> String {
        let totalSeconds = max(0, uptimeMs / 1_000)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours) 时 \(minutes) 分 \(seconds) 秒"
        }
        return "\(minutes) 分 \(seconds) 秒"
    }

    private func icon(for scenario: HardwareDemoPacketScenario) -> String {
        switch scenario {
        case .oneRunning: "play.circle"
        case .mixedWaiting: "person.crop.circle.badge.questionmark"
        case .errorBusy: "exclamationmark.triangle"
        case .fiveTasks: "list.bullet.rectangle"
        case .idle: "moon"
        }
    }

    private var connectionIcon: String {
        switch model.hardwareConnectionState {
        case .disconnected: "antenna.radiowaves.left.and.right.slash"
        case .scanning: "dot.radiowaves.left.and.right"
        case .connecting: "point.3.connected.trianglepath.dotted"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var connectionTint: Color {
        switch model.hardwareConnectionState {
        case .connected: .green
        case .connecting, .scanning: .blue
        case .failed: .red
        case .disconnected: .secondary
        }
    }
}

private struct CardTitle: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct HealthMetricRow: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 34)
        }
    }
}

private struct HardwareDeviceRow: View {
    var device: HardwareDevice
    var connectionState: HardwareConnectionState
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(signalTint.opacity(0.15))
                Image(systemName: "cpu")
                    .foregroundStyle(signalTint)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.headline)
                    if isCurrentDevice {
                        Text("当前")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 8) {
                    Label("\(device.rssi) dBm", systemImage: signalIcon)
                    Text(relativeLastSeen)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: connect) {
                Label(connectButtonTitle, systemImage: connectButtonIcon)
            }
            .buttonStyle(.bordered)
            .disabled(connectionState.isConnected || connectionState.isConnecting)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isCurrentDevice ? Color.green.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.5))
        )
    }

    private var isCurrentDevice: Bool {
        if case .connected(let id) = connectionState {
            return id == device.id
        }
        return false
    }

    private var isConnectingDevice: Bool {
        if case .connecting(let id) = connectionState {
            return id == device.id
        }
        return false
    }

    private var connectButtonTitle: String {
        if isCurrentDevice {
            return "已连接"
        }
        if isConnectingDevice {
            return "连接中"
        }
        if connectionState.isConnected {
            return "先断开"
        }
        return "连接"
    }

    private var connectButtonIcon: String {
        if isCurrentDevice {
            return "checkmark.circle"
        }
        if isConnectingDevice {
            return "ellipsis"
        }
        if connectionState.isConnected {
            return "lock"
        }
        return "link"
    }

    private var signalIcon: String {
        switch device.rssi {
        case (-55)...:
            return "wifi"
        case -70 ..< -55:
            return "wifi.exclamationmark"
        default:
            return "wifi.slash"
        }
    }

    private var signalTint: Color {
        switch device.rssi {
        case (-60)...:
            return .green
        case -78 ..< -60:
            return .orange
        default:
            return .red
        }
    }

    private var relativeLastSeen: String {
        let elapsedSeconds = max(0, Int(Date().timeIntervalSince(device.lastSeen)))
        if elapsedSeconds < 5 {
            return "刚刚发现"
        }
        if elapsedSeconds < 60 {
            return "\(elapsedSeconds) 秒前"
        }
        return "\(elapsedSeconds / 60) 分钟前"
    }
}
