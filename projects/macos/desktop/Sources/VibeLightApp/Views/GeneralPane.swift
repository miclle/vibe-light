import SwiftUI
import VibeLightCore

struct GeneralPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        Form {
            Section("当前状态") {
                LabeledContent("硬件显示状态", value: model.currentState.title)
                LabeledContent("事件桥接", value: model.bridgeMessage)
                if let packet = model.latestPacket {
                    LabeledContent("最近来源", value: packet.source.displayName)
                    if let detail = packet.detail {
                        LabeledContent("聚合摘要", value: detail)
                    }
                    LabeledContent("协议版本", value: "\(packet.v)")
                }
            }

            Section("手动控制") {
                Picker("状态", selection: $model.selectedManualState) {
                    ForEach(DisplayState.allCases) { state in
                        Text(state.title).tag(state)
                    }
                }
                Button {
                    model.recordManualState()
                } label: {
                    Label("写入手动状态", systemImage: "bolt.horizontal.circle")
                }
            }

            Section("偏好") {
                Toggle("开机启动", isOn: $model.launchAtLogin)
                Toggle("启动后自动连接 VibeLight 设备", isOn: $model.autoConnectDevice)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("通用")
    }
}
