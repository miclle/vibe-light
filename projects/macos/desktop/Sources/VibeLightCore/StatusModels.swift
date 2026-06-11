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
    public var fiveHourResetAtMilliseconds: Int64?
    public var weeklyResetAtMilliseconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case fiveHourRemainingPercent
        case weeklyRemainingPercent
        case contextUsedPercent
        case contextRemainingPercent
        case fiveHourResetAtMilliseconds
        case weeklyResetAtMilliseconds
    }

    public init(
        fiveHourRemainingPercent: Int? = nil,
        weeklyRemainingPercent: Int? = nil,
        contextUsedPercent: Int? = nil,
        fiveHourResetAtMilliseconds: Int64? = nil,
        weeklyResetAtMilliseconds: Int64? = nil
    ) {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent.map(Self.clampedPercent)
        self.weeklyRemainingPercent = weeklyRemainingPercent.map(Self.clampedPercent)
        self.contextUsedPercent = contextUsedPercent.map(Self.clampedPercent)
        self.fiveHourResetAtMilliseconds = fiveHourResetAtMilliseconds
        self.weeklyResetAtMilliseconds = weeklyResetAtMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRemaining = try container.decodeIfPresent(Int.self, forKey: .contextRemainingPercent)
        self.init(
            fiveHourRemainingPercent: try container.decodeIfPresent(Int.self, forKey: .fiveHourRemainingPercent),
            weeklyRemainingPercent: try container.decodeIfPresent(Int.self, forKey: .weeklyRemainingPercent),
            contextUsedPercent: try container.decodeIfPresent(Int.self, forKey: .contextUsedPercent) ?? legacyRemaining.map { 100 - $0 },
            fiveHourResetAtMilliseconds: try container.decodeIfPresent(Int64.self, forKey: .fiveHourResetAtMilliseconds),
            weeklyResetAtMilliseconds: try container.decodeIfPresent(Int64.self, forKey: .weeklyResetAtMilliseconds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fiveHourRemainingPercent, forKey: .fiveHourRemainingPercent)
        try container.encodeIfPresent(weeklyRemainingPercent, forKey: .weeklyRemainingPercent)
        try container.encodeIfPresent(contextUsedPercent, forKey: .contextUsedPercent)
        try container.encodeIfPresent(fiveHourResetAtMilliseconds, forKey: .fiveHourResetAtMilliseconds)
        try container.encodeIfPresent(weeklyResetAtMilliseconds, forKey: .weeklyResetAtMilliseconds)
    }

    private static func clampedPercent(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

public struct StatusUsage: Codable, Equatable, Sendable {
    public var codex5hRemainingPercent: Int?
    public var codex7dRemainingPercent: Int?
    public var codex5hResetAt: Int64?
    public var codex7dResetAt: Int64?

    public init(
        codex5hRemainingPercent: Int? = nil,
        codex7dRemainingPercent: Int? = nil,
        codex5hResetAt: Int64? = nil,
        codex7dResetAt: Int64? = nil
    ) {
        self.codex5hRemainingPercent = codex5hRemainingPercent
        self.codex7dRemainingPercent = codex7dRemainingPercent
        self.codex5hResetAt = codex5hResetAt
        self.codex7dResetAt = codex7dResetAt
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

        for candidate in compactedV2Candidates() {
            let candidateData = try candidate.encodedJSON()
            if candidateData.count <= maximumWriteLength {
                return candidateData
            }
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

    private func compactedV2Candidates() -> [StatusPacket] {
        guard let tasks, !tasks.isEmpty else {
            var candidate = self
            candidate.v = 2
            candidate.activeCount = nil
            candidate.waitingCount = nil
            candidate.errorCount = nil
            return [candidate]
        }

        func compactedUsage(keepResetHints: Bool) -> StatusUsage? {
            guard let usage else {
                return nil
            }

            let fiveHourResetAt = keepResetHints && (usage.codex5hRemainingPercent ?? 100) <= 20
                ? usage.codex5hResetAt
                : nil
            let sevenDayResetAt = keepResetHints && (usage.codex7dRemainingPercent ?? 100) <= 20
                ? usage.codex7dResetAt
                : nil

            return StatusUsage(
                codex5hRemainingPercent: usage.codex5hRemainingPercent,
                codex7dRemainingPercent: usage.codex7dRemainingPercent,
                codex5hResetAt: fiveHourResetAt,
                codex7dResetAt: sevenDayResetAt
            )
        }

        func tasksWithoutContext() -> [StatusTask] {
            tasks.map {
                StatusTask(
                    title: $0.title,
                    state: $0.state,
                    source: $0.source,
                    detail: $0.detail,
                    updatedAtMilliseconds: $0.updatedAtMilliseconds
                )
            }
        }

        func tasksWithoutDetail(keepContext: Bool) -> [StatusTask] {
            tasks.map {
                StatusTask(
                    title: $0.title,
                    state: $0.state,
                    source: $0.source,
                    contextUsedPercent: keepContext ? $0.contextUsedPercent : nil,
                    updatedAtMilliseconds: $0.updatedAtMilliseconds
                )
            }
        }

        var withoutUnusedResetHints = self
        withoutUnusedResetHints.v = 2
        withoutUnusedResetHints.usage = compactedUsage(keepResetHints: true)

        var withoutContext = withoutUnusedResetHints
        withoutContext.tasks = tasksWithoutContext()

        var withoutUsageButWithDetail = withoutContext
        withoutUsageButWithDetail.usage = nil

        var withoutTaskDetail = self
        withoutTaskDetail.v = 2
        withoutTaskDetail.tasks = tasksWithoutDetail(keepContext: true)
        withoutTaskDetail.usage = compactedUsage(keepResetHints: true)

        var withoutTaskDetailOrContext = withoutTaskDetail
        withoutTaskDetailOrContext.tasks = tasksWithoutDetail(keepContext: false)

        var withoutCounts = withoutTaskDetailOrContext
        withoutCounts.activeCount = nil
        withoutCounts.waitingCount = nil
        withoutCounts.errorCount = nil

        var withoutDetail = withoutCounts
        withoutDetail.detail = nil

        var withoutUsageOrDetail = withoutDetail
        withoutUsageOrDetail.usage = nil

        return [
            withoutUnusedResetHints,
            withoutContext,
            withoutUsageButWithDetail,
            withoutTaskDetail,
            withoutTaskDetailOrContext,
            withoutCounts,
            withoutDetail,
            withoutUsageOrDetail,
        ]
    }

    private static func truncatedDetail(_ value: String) -> String {
        hardwareSafeTruncated(value, maxUTF8Bytes: maxDetailUTF8Bytes)
    }

    static func truncatedTaskTitle(_ value: String) -> String {
        hardwareSafeTruncated(value, maxUTF8Bytes: maxTaskTitleUTF8Bytes)
    }

    static func truncatedTaskDetail(_ value: String) -> String {
        hardwareSafeTruncated(value, maxUTF8Bytes: maxTaskDetailUTF8Bytes)
    }

    private static func hardwareSafeTruncated(_ value: String, maxUTF8Bytes: Int) -> String {
        truncated(hardwareSafeText(value), maxUTF8Bytes: maxUTF8Bytes)
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

    private static func hardwareSafeText(_ value: String) -> String {
        let replacements: [Character: String] = [
            "⎿": " ",
            "↳": " ",
            "└": " ",
            "╰": " ",
            "╭": " ",
            "│": " ",
            "┃": " ",
            "║": " ",
            "┆": " ",
            "┊": " ",
            "•": "-",
            "●": "-",
            "○": "-",
            "◦": "-",
            "▪": "-",
            "▫": "-",
            "→": ">",
            "⇒": ">",
            "➜": ">",
            "←": "<",
            "✓": "OK",
            "✔": "OK",
            "✗": "X",
            "✖": "X"
        ]

        var result = ""
        var previousWasSpace = true

        func appendHardwareText(_ text: String) {
            for character in text {
                if character.isWhitespace {
                    if !previousWasSpace {
                        result.append(" ")
                        previousWasSpace = true
                    }
                    continue
                }
                result.append(character)
                previousWasSpace = false
            }
        }

        for character in value {
            if let replacement = replacements[character] {
                appendHardwareText(replacement)
            } else if character.isWhitespace {
                appendHardwareText(" ")
            } else if isHardwareDisplayable(character) {
                appendHardwareText(String(character))
            } else if !previousWasSpace {
                result.append(" ")
                previousWasSpace = true
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isHardwareDisplayable(_ character: Character) -> Bool {
        guard !character.unicodeScalars.isEmpty else {
            return false
        }

        return character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x20...0x7E,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF:
                true
            default:
                "。，、！？：；（）【】《》“”‘’·—…".unicodeScalars.contains(scalar)
            }
        }
    }
}

public struct StatusTask: Codable, Equatable, Sendable {
    public var title: String
    public var state: DisplayState
    public var source: VibeSource
    public var detail: String?
    public var contextUsedPercent: Int?
    public var updatedAtMilliseconds: Int64?

    private enum CodingKeys: String, CodingKey {
        case title
        case state
        case source
        case detail
        case contextUsedPercent
        case contextRemainingPercent
        case updatedAt
    }

    public init(
        title: String,
        state: DisplayState,
        source: VibeSource,
        detail: String? = nil,
        contextUsedPercent: Int? = nil,
        updatedAt: Date? = nil,
        updatedAtMilliseconds: Int64? = nil
    ) {
        self.title = StatusPacket.truncatedTaskTitle(title)
        self.state = state
        self.source = source
        self.detail = detail.map { StatusPacket.truncatedTaskDetail($0) }
        self.contextUsedPercent = contextUsedPercent.map { min(100, max(0, $0)) }
        self.updatedAtMilliseconds = updatedAtMilliseconds ?? updatedAt.map {
            Int64(($0.timeIntervalSince1970 * 1_000).rounded())
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyRemaining = try container.decodeIfPresent(Int.self, forKey: .contextRemainingPercent)
        self.init(
            title: try container.decode(String.self, forKey: .title),
            state: try container.decode(DisplayState.self, forKey: .state),
            source: try container.decode(VibeSource.self, forKey: .source),
            detail: try container.decodeIfPresent(String.self, forKey: .detail),
            contextUsedPercent: try container.decodeIfPresent(Int.self, forKey: .contextUsedPercent) ?? legacyRemaining.map { 100 - $0 },
            updatedAtMilliseconds: try container.decodeIfPresent(Int64.self, forKey: .updatedAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(state, forKey: .state)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(detail, forKey: .detail)
        try container.encodeIfPresent(contextUsedPercent, forKey: .contextUsedPercent)
        try container.encodeIfPresent(updatedAtMilliseconds, forKey: .updatedAt)
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
