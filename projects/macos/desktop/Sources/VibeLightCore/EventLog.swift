import Foundation

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
            source: payload.source ?? defaultSource,
            kind: kind,
            detail: detail,
            summary: summary,
            message: message,
            toolName: stringValue(for: ["tool_name", "toolName"], in: object),
            workspace: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            rawPayload: rawPayload
        )
    }

    private func hookEventKind(from object: [String: Any]) -> HookEventKind? {
        stringValue(for: ["hook_event_name", "hookEventName"], in: object)
            .flatMap(HookEventKind.init(rawValue:))
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

    public init(directory: URL = EventLog.defaultDirectory()) {
        self.directory = directory
    }

    public var fileURL: URL {
        directory.appendingPathComponent("events.jsonl", isDirectory: false)
    }

    public func append(_ event: VibeHookEvent) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

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
}
