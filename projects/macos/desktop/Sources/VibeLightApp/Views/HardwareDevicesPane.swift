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

                        Button {
                            model.sendLatestPacketToHardware()
                        } label: {
                            Label("发送当前状态", systemImage: "paperplane")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 190)

            Divider()

            List(model.hardwareDevices) { device in
                HardwareDeviceRow(device: device) {
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
}

private struct HardwareDeviceRow: View {
    var device: HardwareDevice
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
        }
        .padding(.vertical, 6)
    }
}
