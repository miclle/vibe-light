import SwiftUI
import VibeLightCore

struct AgentInstallPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        Form {
            Section("状态") {
                Text(model.agentInstallMessage)
                    .foregroundStyle(.secondary)
            }

            Section("智能体 Hooks") {
                ForEach(AgentKind.allCases) { agent in
                    AgentInstallRow(
                        agent: agent,
                        status: model.agentStatuses[agent],
                        install: { model.installAgent(agent) },
                        uninstall: { model.uninstallAgent(agent) }
                    )
                }
            }

            Section("配置说明") {
                Text("Codex 会写入 ~/.codex/hooks.json，并确保 ~/.codex/config.toml 开启 [features].hooks。Claude 会写入 ~/.claude/settings.json。卸载只移除 Vibe Light 管理的 hook。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("智能体安装")
        .toolbar {
            Button {
                model.refreshAgentStatuses()
            } label: {
                Label("刷新安装状态", systemImage: "arrow.clockwise")
            }
            .help("刷新安装状态")
        }
    }
}

private struct AgentInstallRow: View {
    var agent: AgentKind
    var status: AgentInstallationStatus?
    var install: () -> Void
    var uninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: status?.isInstalled == true ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(status?.isInstalled == true ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(agent.displayName)
                    .font(.headline)
                Text(status?.message ?? "未检查")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                if let path = status?.configURL.path {
                    Text(path)
                        .foregroundStyle(.tertiary)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if status?.isInstalled == true {
                Button("卸载", role: .destructive, action: uninstall)
            } else {
                Button("安装", action: install)
            }
        }
        .padding(.vertical, 4)
    }
}
