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
    public var contextUsedTokens: Int?
    public var contextWindowTokens: Int?

    public init(
        id: String,
        identityKind: TaskIdentityKind,
        source: VibeSource,
        state: DisplayState,
        title: String,
        lastDetail: String,
        lastUpdated: Date,
        inclusionReason: String,
        contextUsedPercent: Int? = nil,
        contextUsedTokens: Int? = nil,
        contextWindowTokens: Int? = nil
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
        self.contextUsedTokens = contextUsedTokens
        self.contextWindowTokens = contextWindowTokens
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
                    contextUsedPercent: $0.contextUsedPercent,
                    contextUsedTokens: $0.contextUsedTokens,
                    contextWindowTokens: $0.contextWindowTokens,
                    updatedAt: $0.lastUpdated
                )
            },
            usage: codexUsage.map {
                StatusUsage(
                    codex5hRemainingPercent: $0.fiveHourRemainingPercent,
                    codex7dRemainingPercent: $0.weeklyRemainingPercent,
                    codex5hResetAt: $0.fiveHourResetAtMilliseconds,
                    codex7dResetAt: $0.weeklyResetAtMilliseconds
                )
            }
        )
    }
}

public struct TaskTracker: Sendable {
    public var staleAfter: TimeInterval
    private let detailFormatter = TaskDetailFormatter()
    private let codexUsageResolver = CodexUsageResolver()

    public init(staleAfter: TimeInterval = 10 * 60) {
        self.staleAfter = staleAfter
    }

    public func snapshot(from newestFirstEvents: [VibeHookEvent], now: Date = Date()) -> DisplaySnapshot {
        var tasksByID: [String: TrackedTask] = [:]
        var usageCache: [String: CodexUsage] = [:]
        var usageMisses = Set<String>()
        let codexUsage = newestFirstEvents.lazy.compactMap {
            codexUsageResolver.resolve(for: $0, cache: &usageCache, misses: &usageMisses)
        }.first

        for event in newestFirstEvents.reversed() where shouldTrack(event) {
            let identity = resolvedIdentity(for: event)
            let usage = codexUsageResolver.resolve(for: event, cache: &usageCache, misses: &usageMisses)
            tasksByID[identity.id] = TrackedTask(
                id: identity.id,
                identityKind: identity.kind,
                source: event.source,
                state: event.displayState,
                title: title(for: event, taskID: identity.id),
                lastDetail: taskDetail(for: event),
                lastUpdated: event.timestamp,
                inclusionReason: inclusionReason(for: event, identity: identity),
                contextUsedPercent: usage?.contextUsedPercent,
                contextUsedTokens: usage?.contextUsedTokens,
                contextWindowTokens: usage?.contextWindowTokens
            )
        }

        let tasks = tasksByID.values
            .filter { task in
                now.timeIntervalSince(task.lastUpdated) <= staleAfter
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
        let visibleTasks = activeTasks
        let state = activeTasks.isEmpty ? .idle : aggregateState(for: tasks)
        let waitingCount = tasks.filter { $0.state == .waiting }.count
        let busyCount = tasks.filter { $0.state == .busy }.count
        let errorCount = tasks.filter { $0.state == .error }.count

        return DisplaySnapshot(
            source: aggregateSource(for: visibleTasks.isEmpty ? [primary] : visibleTasks),
            state: state,
            detail: activeTasks.isEmpty ? lastResultDetail(for: primary) : detail(for: tasks, state: state, primary: primary),
            timestamp: now,
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

    private func lastResultDetail(for task: TrackedTask) -> String {
        let result = task.lastDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? task.title : task.lastDetail
        switch task.state {
        case .success:
            return "LAST OK \(result)"
        case .error:
            return "LAST ERR \(result)"
        default:
            return "no active tasks"
        }
    }

    private func taskDetail(for event: VibeHookEvent) -> String {
        detailFormatter.detail(
            toolName: event.toolName,
            message: event.message,
            state: event.displayState,
            fallback: event.displayDetail
        )
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
