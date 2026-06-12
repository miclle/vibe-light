import AppKit
import SwiftUI

private let mainWindowMinimumSize = NSSize(width: 1040, height: 680)

@main
struct VibeLightApp: App {
    @StateObject private var model = VibeLightAppModel()

    init() {
        if let iconURL = AppResourceBundle.bundle.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("Vibe Light") {
            ContentView(model: model)
                .frame(
                    minWidth: mainWindowMinimumSize.width,
                    minHeight: mainWindowMinimumSize.height
                )
                .background(WindowMinimumSizeSetter(minSize: mainWindowMinimumSize))
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

private struct WindowMinimumSizeSetter: NSViewRepresentable {
    var minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.minSize = minSize
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.minSize = minSize
        }
    }
}
