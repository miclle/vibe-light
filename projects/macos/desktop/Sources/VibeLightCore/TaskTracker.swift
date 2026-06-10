import Foundation

public struct TrackedTask: Equatable, Identifiable, Sendable {
    public var id: String
    public var identityKind: TaskIdentityKind
    public var source: VibeSource
    public var state: DisplayState
    public var title: String
    public var lastDetail: String
    public var lastUpdated: Date
    public var inclusionReason: String
    public var contextUsedPercent: Int?

    public init(
        id: String,
        identityKind: TaskIdentityKind,
        source: VibeSource,
        state: DisplayState,
        title: String,
        lastDetail: String,
        lastUpdated: Date,
        inclusionReason: String,
        contextUsedPercent: Int? = nil
    ) {
        self.id = id
        self.identityKind = identityKind
        self.source = source
        self.state = state
        self.title = title
        self.lastDetail = lastDetail
        self.lastUpdated = lastUpdated
        self.inclusionReason = inclusionReason
        self.contextUsedPercent = contextUsedPercent
    }
}

public enum TaskIdentityKind: String, Codable, Equatable, Sendable {
    case explicit
    case workspace
    case source

    public var title: String {
        switch self {
        case .explicit:
            "session id"
        case .workspace:
            "workspace fallback"
        case .source:
            "source fallback"
        }
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public var source: VibeSource
    public var state: DisplayState
    public var detail: String
    public var timestamp: Date
    public var tasks: [TrackedTask]
    public var staleAfter: TimeInterval
    public var activeCount: Int
    public var waitingCount: Int
    public var errorCount: Int
    public var codexUsage: CodexUsage?

    public init(
        source: VibeSource,
        state: DisplayState,
        detail: String,
        timestamp: Date,
        tasks: [TrackedTask],
        staleAfter: TimeInterval,
        activeCount: Int = 0,
        waitingCount: Int = 0,
        errorCount: Int = 0,
        codexUsage: CodexUsage? = nil
    ) {
        self.source = source
        self.state = state
        self.detail = detail
        self.timestamp = timestamp
        self.tasks = tasks
        self.staleAfter = staleAfter
        self.activeCount = activeCount
        self.waitingCount = waitingCount
        self.errorCount = errorCount
        self.codexUsage = codexUsage
    }

    public var statusPacket: StatusPacket {
        StatusPacket(
            v: 2,
            source: source,
            state: state,
            detail: detail,
            timestamp: timestamp,
            activeCount: activeCount,
            waitingCount: waitingCount,
            errorCount: errorCount,
            tasks: tasks.map {
                StatusTask(
                    title: $0.title,
                    state: $0.state,
                    source: $0.source,
                    detail: $0.lastDetail,
                    contextUsedPercent: $0.contextUsedPercent
                )
            },
            usage: codexUsage.map {
                StatusUsage(
                    codex5hRemainingPercent: $0.fiveHourRemainingPercent,
                    codex7dRemainingPercent: $0.weeklyRemainingPercent
                )
            }
        )
    }
}

public struct TaskTracker: Sendable {
    public var staleAfter: TimeInterval

    public init(staleAfter: TimeInterval = 10 * 60) {
        self.staleAfter = staleAfter
    }

    public func snapshot(from newestFirstEvents: [VibeHookEvent], now: Date = Date()) -> DisplaySnapshot {
        var tasksByID: [String: TrackedTask] = [:]
        var usageCache: [String: CodexUsage] = [:]
        var usageMisses = Set<String>()
        let codexUsage = newestFirstEvents.lazy.compactMap {
            resolvedCodexUsage(for: $0, cache: &usageCache, misses: &usageMisses)
        }.first

        for event in newestFirstEvents.reversed() where shouldTrack(event) {
            let identity = resolvedIdentity(for: event)
            let usage = resolvedCodexUsage(for: event, cache: &usageCache, misses: &usageMisses)
            tasksByID[identity.id] = TrackedTask(
                id: identity.id,
                identityKind: identity.kind,
                source: event.source,
                state: event.displayState,
                title: title(for: event, taskID: identity.id),
                lastDetail: taskDetail(for: event),
                lastUpdated: event.timestamp,
                inclusionReason: inclusionReason(for: event, identity: identity),
                contextUsedPercent: usage?.contextUsedPercent
            )
        }

        let tasks = tasksByID.values
            .filter { task in
                task.state != .busy && task.state != .waiting
                    ? true
                    : now.timeIntervalSince(task.lastUpdated) <= staleAfter
            }
            .sorted { lhs, rhs in
                if priority(lhs.state) != priority(rhs.state) {
                    return priority(lhs.state) < priority(rhs.state)
                }
                return lhs.lastUpdated > rhs.lastUpdated
            }

        guard let primary = tasks.first else {
            return DisplaySnapshot(
                source: .other,
                state: .idle,
                detail: "no active tasks",
                timestamp: now,
                tasks: [],
                staleAfter: staleAfter,
                codexUsage: codexUsage
            )
        }

        let activeTasks = tasks.filter { $0.state == .busy || $0.state == .waiting }
        let visibleTasks = activeTasks.isEmpty ? [primary] : activeTasks
        let state = aggregateState(for: tasks)
        let waitingCount = tasks.filter { $0.state == .waiting }.count
        let busyCount = tasks.filter { $0.state == .busy }.count
        let errorCount = tasks.filter { $0.state == .error }.count

        return DisplaySnapshot(
            source: aggregateSource(for: visibleTasks),
            state: state,
            detail: detail(for: tasks, state: state, primary: primary),
            timestamp: primary.lastUpdated,
            tasks: Array(visibleTasks.prefix(5)),
            staleAfter: staleAfter,
            activeCount: busyCount + waitingCount,
            waitingCount: waitingCount,
            errorCount: errorCount,
            codexUsage: codexUsage
        )
    }

    private func shouldTrack(_ event: VibeHookEvent) -> Bool {
        if event.source == .codex,
           event.workspace == "memories",
           event.displayDetail.contains("Memory Writing Agent") {
            return false
        }

        return true
    }

    private func resolvedCodexUsage(
        for event: VibeHookEvent,
        cache: inout [String: CodexUsage],
        misses: inout Set<String>
    ) -> CodexUsage? {
        if let codexUsage = event.codexUsage {
            return codexUsage
        }
        guard let transcriptPath = codexTranscriptPath(for: event) else {
            return nil
        }

        if let cached = cache[transcriptPath] {
            return cached
        }
        if misses.contains(transcriptPath) {
            return nil
        }

        guard let usage = CodexUsageReader().readLatest(from: URL(fileURLWithPath: transcriptPath)) else {
            misses.insert(transcriptPath)
            return nil
        }

        cache[transcriptPath] = usage
        return usage
    }

    private func codexTranscriptPath(for event: VibeHookEvent) -> String? {
        guard event.source == .codex,
              let rawPayload = event.rawPayload,
              let data = rawPayload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return stringValue(for: ["transcript_path", "transcriptPath"], in: object)
    }

    private func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func resolvedIdentity(for event: VibeHookEvent) -> (id: String, kind: TaskIdentityKind) {
        if let taskID = event.taskID, !taskID.isEmpty {
            return (taskID, .explicit)
        }

        if let workspace = event.workspace, !workspace.isEmpty {
            return ("\(event.source.rawValue):\(workspace)", .workspace)
        }

        return (event.source.rawValue, .source)
    }

    private func inclusionReason(
        for event: VibeHookEvent,
        identity: (id: String, kind: TaskIdentityKind)
    ) -> String {
        switch event.displayState {
        case .busy:
            "active busy task from \(identity.kind.title)"
        case .waiting:
            "waiting task from \(identity.kind.title)"
        case .success:
            "recent success from \(identity.kind.title)"
        case .error:
            "recent error from \(identity.kind.title)"
        case .idle:
            "idle task from \(identity.kind.title)"
        case .offline:
            "offline task from \(identity.kind.title)"
        }
    }

    private func title(for event: VibeHookEvent, taskID: String) -> String {
        if let workspace = event.workspace, !workspace.isEmpty {
            return workspace
        }
        if let toolName = event.toolName, !toolName.isEmpty {
            return toolName
        }
        return taskID
    }

    private func taskDetail(for event: VibeHookEvent) -> String {
        guard let toolName = event.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            return event.displayDetail
        }

        guard let message = event.message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return toolName
        }

        return "\(toolName) / \(compactToolAction(message, toolName: toolName))"
    }

    private func compactToolAction(_ message: String, toolName: String) -> String {
        let firstLine = message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? message

        if shouldCompactAsPath(firstLine, toolName: toolName) {
            let lastComponent = URL(fileURLWithPath: firstLine).lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }

        return firstLine
    }

    private func shouldCompactAsPath(_ value: String, toolName: String) -> Bool {
        let normalizedToolName = toolName.lowercased()
        if normalizedToolName == "bash" {
            return false
        }

        return !value.contains(" ") && value.contains("/")
    }

    private func aggregateState(for tasks: [TrackedTask]) -> DisplayState {
        if tasks.contains(where: { $0.state == .waiting }) {
            return .waiting
        }
        if tasks.contains(where: { $0.state == .busy }) {
            return .busy
        }
        if tasks.contains(where: { $0.state == .error }) {
            return .error
        }
        if tasks.contains(where: { $0.state == .success }) {
            return .success
        }
        return .idle
    }

    private func aggregateSource(for tasks: [TrackedTask]) -> VibeSource {
        let sources = Set(tasks.map(\.source))
        return sources.count == 1 ? tasks.first?.source ?? .other : .other
    }

    private func detail(for tasks: [TrackedTask], state: DisplayState, primary: TrackedTask) -> String {
        let waitingCount = tasks.filter { $0.state == .waiting }.count
        let busyCount = tasks.filter { $0.state == .busy }.count
        let errorCount = tasks.filter { $0.state == .error }.count

        var parts: [String] = []
        if busyCount > 0 {
            parts.append("\(busyCount) running")
        }
        if waitingCount > 0 {
            parts.append("\(waitingCount) waiting")
        }
        if errorCount > 0, state == .error {
            parts.append("\(errorCount) error")
        }

        if parts.isEmpty {
            return "\(primary.title): \(primary.state.rawValue)"
        }

        return parts.joined(separator: " · ")
    }

    private func priority(_ state: DisplayState) -> Int {
        switch state {
        case .waiting:
            0
        case .busy:
            1
        case .error:
            2
        case .success:
            3
        case .idle:
            4
        case .offline:
            5
        }
    }
}
