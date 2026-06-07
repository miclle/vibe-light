import SwiftUI
import VibeLightCore

struct ContentView: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedTab) {
                Section("Vibe Light") {
                    ForEach(AppTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.selectedTab {
                case .general:
                    GeneralPane(model: model)
                case .setup:
                    SetupPane(model: model)
                case .events:
                    EventsPane(model: model)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        model.refreshEvents()
                    } label: {
                        Label("刷新事件", systemImage: "arrow.clockwise")
                    }
                    .help("刷新事件")
                }
            }
        }
        .task {
            await model.pollEvents()
        }
    }
}
