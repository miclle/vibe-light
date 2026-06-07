import SwiftUI

@main
struct VibeLightApp: App {
    @StateObject private var model = VibeLightAppModel()

    var body: some Scene {
        WindowGroup("Vibe Light") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("刷新事件") {
                    model.refreshEvents()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsWindowView(model: model)
                .frame(width: 520, height: 360)
        }
    }
}
