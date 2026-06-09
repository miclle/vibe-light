import Foundation

public enum VibeSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case codex
    case claude
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .manual: "手动"
        case .codex: "Codex"
        case .claude: "Claude"
        case .other: "其他"
        }
    }
}

public enum DisplayState: String, Codable, CaseIterable, Identifiable, Sendable {
    case idle
    case busy
    case waiting
    case success
    case error
    case offline

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .idle: "空闲"
        case .busy: "运行中"
        case .waiting: "等待处理"
        case .success: "已完成"
        case .error: "需要处理"
        case .offline: "未连接"
        }
    }

    public var diagnosticDetail: String {
        switch self {
        case .idle: "idle"
        case .busy: "running"
        case .waiting: "waiting"
        case .success: "completed"
        case .error: "failed"
        case .offline: "offline"
        }
    }
}

public enum HookEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
    case postToolUseFailure = "PostToolUseFailure"
    case stopFailure = "StopFailure"
    case permissionDenied = "PermissionDenied"

    public var id: String { rawValue }

    public var displayState: DisplayState {
        switch self {
        case .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse:
            .busy
        case .permissionRequest:
            .waiting
        case .stop, .sessionEnd:
            .success
        case .postToolUseFailure, .stopFailure, .permissionDenied:
            .error
        }
    }
}

public struct VibeHookEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var taskID: String?
    public var source: VibeSource
    public var kind: HookEventKind
    public var detail: String
    public var timestamp: Date
    public var summary: String?
    public var message: String?
    public var toolName: String?
    public var workspace: String?
    public var rawPayload: String?
    public var codexUsage: CodexUsage?

    public init(
        id: UUID = UUID(),
        taskID: String? = nil,
        source: VibeSource,
        kind: HookEventKind,
        detail: String = "",
        timestamp: Date = Date(),
        summary: String? = nil,
        message: String? = nil,
        toolName: String? = nil,
        workspace: String? = nil,
        rawPayload: String? = nil,
        codexUsage: CodexUsage? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.source = source
        self.kind = kind
        self.detail = detail
        self.timestamp = timestamp
        self.summary = summary
        self.message = message
        self.toolName = toolName
        self.workspace = workspace
        self.rawPayload = rawPayload
        self.codexUsage = codexUsage
    }

    public var displayState: DisplayState {
        kind.displayState
    }

    public var displayDetail: String {
        summary ?? (detail.isEmpty ? kind.rawValue : detail)
    }
}

public struct CodexUsage: Codable, Equatable, Sendable {
    public var fiveHourRemainingPercent: Int?
    public var weeklyRemainingPercent: Int?
    public var contextUsedPercent: Int?

    private enum CodingKeys: String, CodingKey {
        case fiveHourRemainingPercent
        case weeklyRemainingPercent
        case contextUsedPercent
        case contextRemainingPercent
    }

    public init(
        fiveHourRemainingPercent: Int? = nil,
        weeklyRemainingPercent: Int? = nil,
        contextUsedPercent: Int? = nil
    ) {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent.map(Self.clampedPercent)
        self.weeklyRemainingPercent = weeklyRemainingPercent.map(Self.clampedPercent)
        self.contextUsedPercent = contextUsedPercent.map(Self.clampedPercent)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRemaining = try container.decodeIfPresent(Int.self, forKey: .contextRemainingPercent)
        self.init(
            fiveHourRemainingPercent: try container.decodeIfPresent(Int.self, forKey: .fiveHourRemainingPercent),
            weeklyRemainingPercent: try container.decodeIfPresent(Int.self, forKey: .weeklyRemainingPercent),
            contextUsedPercent: try container.decodeIfPresent(Int.self, forKey: .contextUsedPercent) ?? legacyRemaining.map { 100 - $0 }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fiveHourRemainingPercent, forKey: .fiveHourRemainingPercent)
        try container.encodeIfPresent(weeklyRemainingPercent, forKey: .weeklyRemainingPercent)
        try container.encodeIfPresent(contextUsedPercent, forKey: .contextUsedPercent)
    }

    private static func clampedPercent(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

public struct StatusUsage: Codable, Equatable, Sendable {
    public var codex5hRemainingPercent: Int?
    public var codex7dRemainingPercent: Int?

    public init(codex5hRemainingPercent: Int? = nil, codex7dRemainingPercent: Int? = nil) {
        self.codex5hRemainingPercent = codex5hRemainingPercent
        self.codex7dRemainingPercent = codex7dRemainingPercent
    }
}

public struct StatusPacket: Codable, Equatable, Sendable {
    public static let maxDetailUTF8Bytes = 80
    public static let maxTaskTitleUTF8Bytes = 32
    public static let maxTaskDetailUTF8Bytes = 40

    public var v: Int
    public var source: VibeSource
    public var state: DisplayState
    public var detail: String?
    public var ts: Int64
    public var activeCount: Int?
    public var waitingCount: Int?
    public var errorCount: Int?
    public var tasks: [StatusTask]?
    public var usage: StatusUsage?

    public init(
        v: Int = 1,
        source: VibeSource,
        state: DisplayState,
        detail: String? = nil,
        timestamp: Date = Date(),
        activeCount: Int? = nil,
        waitingCount: Int? = nil,
        errorCount: Int? = nil,
        tasks: [StatusTask]? = nil,
        usage: StatusUsage? = nil
    ) {
        self.v = v
        self.source = source
        self.state = state
        self.detail = detail.map { Self.truncatedDetail($0) }
        self.ts = Int64((timestamp.timeIntervalSince1970 * 1_000).rounded())
        self.activeCount = activeCount
        self.waitingCount = waitingCount
        self.errorCount = errorCount
        self.tasks = tasks
        self.usage = usage
    }

    public init(event: VibeHookEvent) {
        self.init(
            source: event.source,
            state: event.displayState,
            detail: event.displayDetail,
            timestamp: event.timestamp
        )
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public func encodedJSON(maximumWriteLength: Int) throws -> Data {
        let data = try encodedJSON()
        guard data.count > maximumWriteLength, v >= 2 else {
            return data
        }

        var fallback = self
        fallback.v = 1
        fallback.activeCount = nil
        fallback.waitingCount = nil
        fallback.errorCount = nil
        fallback.tasks = nil
        fallback.usage = nil
        return try fallback.encodedJSON()
    }

    private static func truncatedDetail(_ value: String) -> String {
        truncated(value, maxUTF8Bytes: maxDetailUTF8Bytes)
    }

    static func truncatedTaskTitle(_ value: String) -> String {
        truncated(value, maxUTF8Bytes: maxTaskTitleUTF8Bytes)
    }

    static func truncatedTaskDetail(_ value: String) -> String {
        truncated(value, maxUTF8Bytes: maxTaskDetailUTF8Bytes)
    }

    fileprivate static func truncated(_ value: String, maxUTF8Bytes: Int) -> String {
        var result = ""
        var usedBytes = 0

        for character in value {
            let byteCount = character.utf8.count
            if usedBytes + byteCount > maxUTF8Bytes {
                break
            }

            result.append(character)
            usedBytes += byteCount
        }

        return result
    }
}

public struct StatusTask: Codable, Equatable, Sendable {
    public var title: String
    public var state: DisplayState
    public var source: VibeSource
    public var detail: String?
    public var contextUsedPercent: Int?

    private enum CodingKeys: String, CodingKey {
        case title
        case state
        case source
        case detail
        case contextUsedPercent
        case contextRemainingPercent
    }

    public init(
        title: String,
        state: DisplayState,
        source: VibeSource,
        detail: String? = nil,
        contextUsedPercent: Int? = nil
    ) {
        self.title = StatusPacket.truncatedTaskTitle(title)
        self.state = state
        self.source = source
        self.detail = detail.map { StatusPacket.truncatedTaskDetail($0) }
        self.contextUsedPercent = contextUsedPercent.map { min(100, max(0, $0)) }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRemaining = try container.decodeIfPresent(Int.self, forKey: .contextRemainingPercent)
        self.init(
            title: try container.decode(String.self, forKey: .title),
            state: try container.decode(DisplayState.self, forKey: .state),
            source: try container.decode(VibeSource.self, forKey: .source),
            detail: try container.decodeIfPresent(String.self, forKey: .detail),
            contextUsedPercent: try container.decodeIfPresent(Int.self, forKey: .contextUsedPercent) ?? legacyRemaining.map { 100 - $0 }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(contextUsedPercent, forKey: .contextUsedPercent)
    }
}

public struct HealthPacket: Codable, Equatable, Sendable {
    public var v: Int
    public var device: String
    public var uptimeMs: Int64
    public var connected: Bool
    public var lastState: DisplayState

    public init(
        v: Int = 1,
        device: String,
        uptimeMs: Int64,
        connected: Bool,
        lastState: DisplayState
    ) {
        self.v = v
        self.device = device
        self.uptimeMs = uptimeMs
        self.connected = connected
        self.lastState = lastState
    }
}
