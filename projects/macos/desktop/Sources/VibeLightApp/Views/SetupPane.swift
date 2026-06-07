import SwiftUI
import VibeLightCore

struct SetupPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        Form {
            Section("安装进度") {
                LabeledContent("完成项", value: "\(model.checklist.completedCount) / \(SetupStep.allCases.count)")
                LabeledContent("状态", value: model.checklist.isReady ? "可以开始同步硬件状态" : "继续完成下面的步骤")
            }

            Section("步骤") {
                ForEach(SetupStep.allCases) { step in
                    Toggle(isOn: Binding(
                        get: { model.checklist.status(for: step) == .complete },
                        set: { model.markSetupStep(step, complete: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                            Text(step.detail)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }

            Section("Hook CLI") {
                Text("将 Codex / Claude hook 的 JSON stdin 转发给 `vibe-light-hook`，事件会写入本机 Application Support 的 `events.jsonl`。")
                    .foregroundStyle(.secondary)
                Text(#"示例：{"source":"codex","event":"PreToolUse","detail":"running shell"}"#)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("安装向导")
    }
}
