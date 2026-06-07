import SwiftUI
import VibeLightCore

struct EventsPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        VStack(spacing: 0) {
            eventSummary
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            List(model.events) { event in
                EventRow(event: event)
            }
            .overlay {
                if model.events.isEmpty {
                    ContentUnavailableView(
                        "暂无事件",
                        systemImage: "tray",
                        description: Text("通过 hook CLI 或通用页的手动控制写入状态后，这里会显示采集到的事件。")
                    )
                }
            }
        }
        .navigationTitle("事件")
    }

    private var eventSummary: some View {
        HStack(spacing: 16) {
            Label(model.currentState.title, systemImage: "circle.fill")
                .foregroundStyle(tint(for: model.currentState))
                .font(.headline)

            Divider()
                .frame(height: 22)

            Text("\(model.events.count) 条最近事件")
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func tint(for state: DisplayState) -> Color {
        switch state {
        case .idle: .secondary
        case .busy: .blue
        case .waiting: .purple
        case .success: .green
        case .error: .red
        case .offline: .orange
        }
    }
}

private struct EventRow: View {
    var event: VibeHookEvent
    @State private var showsRawPayload = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(tint)
                .frame(width: 16)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(primaryTitle)
                        .font(.headline)
                    Text(event.source.displayName)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(event.timestamp, style: .time)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Text(event.displayDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let message = event.message, message != event.displayDetail {
                    Text(message)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    if let workspace = event.workspace {
                        Label(workspace, systemImage: "folder")
                    }
                    Text(event.displayState.title)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                if let rawPayload = event.rawPayload {
                    DisclosureGroup("原始 Payload", isExpanded: $showsRawPayload) {
                        Text(rawPayload)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var primaryTitle: String {
        if let toolName = event.toolName {
            "\(event.kind.rawValue) · \(toolName)"
        } else {
            event.kind.rawValue
        }
    }

    private var tint: Color {
        switch event.displayState {
        case .idle: .secondary
        case .busy: .blue
        case .waiting: .purple
        case .success: .green
        case .error: .red
        case .offline: .orange
        }
    }
}
