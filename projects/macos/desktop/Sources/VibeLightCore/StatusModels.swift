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
        rawPayload: String? = nil
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
    }

    public var displayState: DisplayState {
        kind.displayState
    }

    public var displayDetail: String {
        summary ?? (detail.isEmpty ? kind.rawValue : detail)
    }
}

public struct StatusPacket: Codable, Equatable, Sendable {
    public static let maxDetailUTF8Bytes = 80

    public var v: Int
    public var source: VibeSource
    public var state: DisplayState
    public var detail: String?
    public var ts: Int64

    public init(
        v: Int = 1,
        source: VibeSource,
        state: DisplayState,
        detail: String? = nil,
        timestamp: Date = Date()
    ) {
        self.v = v
        self.source = source
        self.state = state
        self.detail = detail.map { Self.truncatedDetail($0) }
        self.ts = Int64((timestamp.timeIntervalSince1970 * 1_000).rounded())
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

    private static func truncatedDetail(_ value: String) -> String {
        var result = ""
        var usedBytes = 0

        for character in value {
            let byteCount = character.utf8.count
            if usedBytes + byteCount > maxDetailUTF8Bytes {
                break
            }

            result.append(character)
            usedBytes += byteCount
        }

        return result
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
