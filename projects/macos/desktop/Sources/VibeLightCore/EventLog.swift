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
        return VibeHookEvent(
            source: payload.source ?? defaultSource,
            kind: payload.event ?? payload.kind ?? .userPromptSubmit,
            detail: payload.detail ?? ""
        )
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
