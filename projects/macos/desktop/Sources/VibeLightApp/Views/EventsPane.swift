import SwiftUI
import VibeLightCore

struct EventsPane: View {
    @ObservedObject var model: VibeLightAppModel

    var body: some View {
        VStack(spacing: 0) {
            eventSummary
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            if let snapshot = model.displaySnapshot, !snapshot.tasks.isEmpty {
                TaskSnapshotSummary(snapshot: snapshot)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
            }

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
        .toolbar {
            Button {
                model.refreshEvents()
            } label: {
                Label("刷新事件", systemImage: "arrow.clockwise")
            }
            .help("刷新事件")
        }
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

            if let detail = model.latestPacket?.detail {
                Divider()
                    .frame(height: 22)

                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

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

private struct TaskSnapshotSummary: View {
    var snapshot: DisplaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("任务聚合")
                    .font(.headline)
                Spacer()
                Text("\(snapshot.tasks.count) 个任务 · \(formatDuration(snapshot.staleAfter)) 过期")
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshot.tasks) { task in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(task.state.rawValue.uppercased())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(tint(for: task.state))
                            .frame(width: 62, alignment: .leading)

                        Text(task.title)
                            .lineLimit(1)

                        Spacer()

                        Text(task.lastUpdated, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(task.identityKind.title) · \(shortTaskID(task.id)) · \(relativeAge(since: task.lastUpdated)) · \(task.inclusionReason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .font(.callout)
    }

    private func shortTaskID(_ value: String) -> String {
        guard value.count > 18 else {
            return value
        }

        return String(value.suffix(18))
    }

    private func relativeAge(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        return "\(minutes / 60)h ago"
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        return "\(minutes)m"
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
    @State private var isExpanded = false

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
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Payload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(rawPayload.count) bytes")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if isExpanded {
                        PayloadCodeBlock(rawPayload: rawPayload)
                            .padding(.top, 2)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard event.rawPayload != nil else { return }
            withAnimation(.snappy(duration: 0.16)) {
                isExpanded.toggle()
            }
        }
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

private struct PayloadCodeBlock: View {
    var rawPayload: String
    private var displayPayload: String {
        PayloadFormatter.prettyPrintedJSON(rawPayload) ?? rawPayload
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            highlightedJSON(displayPayload)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .frame(maxHeight: 220)
    }

    private func highlightedJSON(_ value: String) -> Text {
        var index = value.startIndex
        var result = Text("")

        while index < value.endIndex {
            let character = value[index]

            if character == "\"" {
                let start = index
                index = value.index(after: index)
                var isEscaped = false

                while index < value.endIndex {
                    let current = value[index]
                    if current == "\"" && !isEscaped {
                        index = value.index(after: index)
                        break
                    }
                    isEscaped = current == "\\" && !isEscaped
                    if current != "\\" {
                        isEscaped = false
                    }
                    index = value.index(after: index)
                }

                let token = String(value[start..<index])
                result = result + Text(token).foregroundColor(isObjectKey(after: index, in: value) ? .blue : .green)
                continue
            }

            if character.isNumber || character == "-" {
                let start = index
                index = value.index(after: index)
                while index < value.endIndex, value[index].isNumber || value[index] == "." {
                    index = value.index(after: index)
                }
                result = result + Text(String(value[start..<index])).foregroundColor(.purple)
                continue
            }

            if let literal = literalToken(startingAt: index, in: value) {
                result = result + Text(literal).foregroundColor(.orange)
                index = value.index(index, offsetBy: literal.count)
                continue
            }

            let token = String(character)
            let color: Color = "{}[]:,".contains(character) ? .secondary : .primary
            result = result + Text(token).foregroundColor(color)
            index = value.index(after: index)
        }

        return result
    }

    private func isObjectKey(after index: String.Index, in value: String) -> Bool {
        var cursor = index
        while cursor < value.endIndex, value[cursor].isWhitespace {
            cursor = value.index(after: cursor)
        }
        return cursor < value.endIndex && value[cursor] == ":"
    }

    private func literalToken(startingAt index: String.Index, in value: String) -> String? {
        for literal in ["true", "false", "null"] {
            guard let end = value.index(index, offsetBy: literal.count, limitedBy: value.endIndex),
                  String(value[index..<end]) == literal else {
                continue
            }
            return literal
        }
        return nil
    }
}
