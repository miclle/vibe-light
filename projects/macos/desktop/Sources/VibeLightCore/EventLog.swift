import Foundation
#if canImport(Darwin)
import Darwin
#endif

public struct HookPayloadDecoder: Sendable {
    private struct Payload: Decodable {
        var source: VibeSource?
        var event: HookEventKind?
        var kind: HookEventKind?
        var detail: String?
    }

    public var defaultSource: VibeSource

    public init(defaultSource: VibeSource = .other) {
        self.defaultSource = defaultSource
    }

    public func decode(_ data: Data) throws -> VibeHookEvent {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let rawPayload = String(data: data, encoding: .utf8)
        let kind = payload.event ?? payload.kind ?? hookEventKind(from: object) ?? .userPromptSubmit
        let detail = payload.detail ?? stringValue(for: ["detail"], in: object) ?? ""
        let toolInput = object["tool_input"] as? [String: Any]
        let cwd = stringValue(for: ["cwd"], in: object)
        let message = extractedMessage(from: object, toolInput: toolInput)
        let summary = extractedSummary(
            detail: detail,
            object: object,
            toolInput: toolInput,
            message: message,
            kind: kind
        )

        return VibeHookEvent(
            taskID: explicitTaskID(from: object, source: payload.source ?? defaultSource),
            source: payload.source ?? defaultSource,
            kind: kind,
            detail: detail,
            summary: summary,
            message: message,
            toolName: stringValue(for: ["tool_name", "toolName"], in: object),
            workspace: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            rawPayload: rawPayload,
            codexUsage: extractedCodexUsage(from: object, source: payload.source ?? defaultSource)
        )
    }

    private func hookEventKind(from object: [String: Any]) -> HookEventKind? {
        stringValue(for: ["hook_event_name", "hookEventName"], in: object)
            .flatMap(HookEventKind.init(rawValue:))
    }

    private func explicitTaskID(from object: [String: Any], source: VibeSource) -> String? {
        if let explicitID = stringValue(
            for: ["task_id", "taskId", "session_id", "sessionId", "conversation_id", "conversationId", "thread_id", "threadId"],
            in: object
        ) {
            return "\(source.rawValue):\(explicitID)"
        }

        return nil
    }

    private func extractedSummary(
        detail: String,
        object: [String: Any],
        toolInput: [String: Any]?,
        message: String?,
        kind: HookEventKind
    ) -> String? {
        firstNonEmpty([
            detail,
            stringValue(for: ["message", "title", "last_assistant_message", "error", "error_details", "prompt"], in: object),
            stringValue(for: ["description"], in: toolInput ?? [:]),
            message,
            kind.rawValue,
        ])
    }

    private func extractedMessage(from object: [String: Any], toolInput: [String: Any]?) -> String? {
        firstNonEmpty([
            stringValue(for: ["command"], in: toolInput ?? [:]),
            stringValue(for: ["file_path", "path"], in: toolInput ?? [:]),
            stringValue(for: ["message", "last_assistant_message", "error", "error_details", "prompt"], in: object),
        ])
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

    private func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private func extractedCodexUsage(from object: [String: Any], source: VibeSource) -> CodexUsage? {
        guard source == .codex,
              let transcriptPath = stringValue(for: ["transcript_path", "transcriptPath"], in: object) else {
            return nil
        }

        return CodexUsageReader().readLatest(from: URL(fileURLWithPath: transcriptPath))
    }

}

public struct CodexUsageReader: Sendable {
    public init() {}

    public func readLatest(from transcriptURL: URL) -> CodexUsage? {
        guard let text = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
            return nil
        }

        for line in text.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count" else {
                continue
            }

            return usage(from: payload)
        }

        return nil
    }

    private func usage(from payload: [String: Any]) -> CodexUsage {
        let info = payload["info"] as? [String: Any]
        let rateLimits = payload["rate_limits"] as? [String: Any]
        let primary = rateLimits?["primary"] as? [String: Any]
        let secondary = rateLimits?["secondary"] as? [String: Any]

        return CodexUsage(
            fiveHourRemainingPercent: remainingPercent(from: primary),
            weeklyRemainingPercent: remainingPercent(from: secondary),
            contextRemainingPercent: contextRemainingPercent(from: info)
        )
    }

    private func remainingPercent(from window: [String: Any]?) -> Int? {
        guard let usedPercent = number(window?["used_percent"]) else {
            return nil
        }

        return clampedPercent(Int((100 - usedPercent).rounded()))
    }

    private func contextRemainingPercent(from info: [String: Any]?) -> Int? {
        guard let window = number(info?["model_context_window"]),
              window > 0 else {
            return nil
        }

        let lastUsage = info?["last_token_usage"] as? [String: Any]
        let totalUsage = info?["total_token_usage"] as? [String: Any]
        guard let contextTokens = number(lastUsage?["input_tokens"]) ?? number(totalUsage?["total_tokens"]) else {
            return nil
        }

        return clampedPercent(Int((100 - (contextTokens / window * 100)).rounded()))
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            value
        case let value as Int:
            Double(value)
        case let value as Int64:
            Double(value)
        case let value as NSNumber:
            value.doubleValue
        default:
            nil
        }
    }

    private func clampedPercent(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

public enum PayloadFormatter {
    public static func prettyPrintedJSON(_ rawPayload: String) -> String? {
        guard let data = rawPayload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let formattedData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            return nil
        }

        return String(data: formattedData, encoding: .utf8)
    }
}

public struct EventLog: Sendable {
    public var directory: URL
    public var retentionLimit: Int

    public init(
        directory: URL = EventLog.defaultDirectory(),
        retentionLimit: Int = 500
    ) {
        self.directory = directory
        self.retentionLimit = max(1, retentionLimit)
    }

    public var fileURL: URL {
        directory.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    public func append(_ event: VibeHookEvent) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        EventLogProcessLock.lock.lock()
        defer { EventLogProcessLock.lock.unlock() }

        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }
        let lockHandle = try FileHandle(forWritingTo: lockURL)
        defer { try? lockHandle.close() }
        try lock(handle: lockHandle)
        defer { unlock(handle: lockHandle) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        var line = data
        line.append(0x0A)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }

        try pruneIfNeeded()
    }

    public func readRecent(limit: Int = 50) throws -> [VibeHookEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(separator: "\n")
            .suffix(max(1, limit))
            .reversed()
            .compactMap { line in
                try? decoder.decode(VibeHookEvent.self, from: Data(line.utf8))
            }
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return base.appendingPathComponent("VibeLight", isDirectory: true)
    }

    private var lockURL: URL {
        directory.appendingPathComponent("events.lock", isDirectory: false)
    }

    private func lock(handle: FileHandle) throws {
        #if canImport(Darwin)
        if flock(handle.fileDescriptor, LOCK_EX) != 0 {
            throw CocoaError(.fileLocking)
        }
        #endif
    }

    private func unlock(handle: FileHandle) {
        #if canImport(Darwin)
        _ = flock(handle.fileDescriptor, LOCK_UN)
        #endif
    }

    private func pruneIfNeeded() throws {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = text.split(separator: "\n")
        guard lines.count > retentionLimit else {
            return
        }

        let retained = lines.suffix(retentionLimit).joined(separator: "\n") + "\n"
        try Data(retained.utf8).write(to: fileURL, options: .atomic)
    }
}

private enum EventLogProcessLock {
    static let lock = NSLock()
}
