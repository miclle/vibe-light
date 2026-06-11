import Foundation

struct CodexUsageResolver: Sendable {
    func resolve(
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
}
