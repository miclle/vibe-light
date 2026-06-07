import SwiftUI

struct SettingsWindowView: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机启动", isOn: $model.launchAtLogin)
                Toggle("启动后自动连接 VibeLight 设备", isOn: $model.autoConnectDevice)
            }

            Section("事件") {
                LabeledContent("轮询间隔", value: "1.5 秒")
                LabeledContent("事件保留", value: "最近 80 条")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
