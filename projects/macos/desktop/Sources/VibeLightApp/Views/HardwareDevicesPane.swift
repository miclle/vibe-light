import SwiftUI
import VibeLightCore

struct HardwareDevicesPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("设备管理") {
                    LabeledContent("连接状态", value: model.hardwareConnectionState.title)
                    LabeledContent("说明", value: model.hardwareMessage)

                    HStack {
                        Button {
                            model.startHardwareScan()
                        } label: {
                            Label("扫描", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(model.isHardwareScanning)

                        Button {
                            model.stopHardwareScan()
                        } label: {
                            Label("停止", systemImage: "stop.circle")
                        }
                        .disabled(!model.isHardwareScanning)

                        Button {
                            model.disconnectHardwareDevice()
                        } label: {
                            Label("断开", systemImage: "xmark.circle")
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
                    }
                }

                Section("设备健康") {
                    if let health = model.hardwareHealthPacket {
                        LabeledContent("设备", value: health.device)
                        LabeledContent("运行时间", value: formatUptime(health.uptimeMs))
                        LabeledContent("连接", value: health.connected ? "已连接" : "未连接")
                        LabeledContent("最近状态", value: health.lastState.title)
                    } else {
                        Text("连接设备后读取健康状态。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 310)

            Divider()

            List(model.hardwareDevices) { device in
                HardwareDeviceRow(device: device, connectionState: model.hardwareConnectionState) {
                    model.connectHardwareDevice(device)
                }
            }
            .overlay {
                if model.hardwareDevices.isEmpty {
                    ContentUnavailableView(
                        "未发现设备",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("点击扫描，查找广播 VibeLight 服务的 ESP32-S3 设备。")
                    )
                }
            }
        }
        .navigationTitle("硬件设备")
    }

    private func formatUptime(_ uptimeMs: Int64) -> String {
        let totalSeconds = max(0, uptimeMs / 1_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes) 分 \(seconds) 秒"
    }
}

private struct HardwareDeviceRow: View {
    var device: HardwareDevice
    var connectionState: HardwareConnectionState
    var connect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.headline)
                Text("RSSI \(device.rssi) dBm")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button("连接", action: connect)
                .disabled(connectionState.isConnected || connectionState.isConnecting)
        }
        .padding(.vertical, 6)
    }
}
