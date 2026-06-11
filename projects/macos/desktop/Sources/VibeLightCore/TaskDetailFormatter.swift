import Foundation

public struct TaskDetailFormatter: Sendable {
    public init() {}

    public func detail(toolName: String?, message: String?, state: DisplayState, fallback: String) -> String {
        guard let toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            return fallback
        }

        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = trimmedMessage.flatMap { message -> String? in
            guard !message.isEmpty else {
                return nil
            }
            return compactToolAction(message, toolName: toolName)
        }

        if state == .waiting {
            return waitingActionDetail(toolName: toolName, action: action)
        }

        guard let action else {
            return toolName
        }

        return "\(toolName) / \(action)"
    }

    private func compactToolAction(_ message: String, toolName: String) -> String {
        let firstLine = message
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? message
        let normalizedToolName = toolName.lowercased()

        if normalizedToolName == "bash" {
            return compactShellAction(firstLine)
        }

        if shouldCompactAsPath(firstLine, toolName: toolName) {
            let lastComponent = URL(fileURLWithPath: firstLine).lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }

        return firstLine
    }

    private func compactShellAction(_ command: String) -> String {
        let normalized = strippedShellPrefix(command)
        let lowered = normalized.lowercased()

        if lowered == "make quick" || lowered.hasPrefix("make quick ") {
            return "TEST make quick"
        }
        if lowered == "make verify" || lowered.hasPrefix("make verify ") {
            return "TEST make verify"
        }
        if lowered == "make esp32-test" || lowered.hasPrefix("make esp32-test ") {
            return "TEST make esp32-test"
        }
        if lowered == "make esp32-build" || lowered.hasPrefix("make esp32-build ") {
            return "BUILD make esp32-build"
        }
        if lowered == "make esp32-flash" || lowered.hasPrefix("make esp32-flash ") ||
            lowered == "make esp32-flash-only" || lowered.hasPrefix("make esp32-flash-only ") {
            return "FLASH \(normalized)"
        }
        if lowered.hasPrefix("idf.py ") {
            return "BUILD idf.py"
        }
        if lowered.hasPrefix("osascript ") {
            return compactAppleScriptAction(from: lowered)
        }
        if lowered.hasPrefix("python ") || lowered.hasPrefix("python3 ") {
            return compactPythonAction(normalized)
        }
        if lowered.hasPrefix("swift test") || lowered.hasPrefix("npm test") ||
            lowered.hasPrefix("pnpm test") || lowered.hasPrefix("yarn test") {
            return "TEST \(firstShellWords(normalized, count: 2))"
        }
        if lowered.hasPrefix("git ") {
            return "GIT \(firstShellWords(String(normalized.dropFirst(4)).trimmingCharacters(in: .whitespaces), count: 1))"
        }
        if lowered.hasPrefix("rg ") {
            return "SEARCH \(firstSearchTerm(from: String(normalized.dropFirst(3)).trimmingCharacters(in: .whitespaces)))"
        }
        if lowered.hasPrefix("sed ") {
            let last = normalized.split(separator: " ").last.map(String.init) ?? normalized
            let fileName = URL(fileURLWithPath: last).lastPathComponent
            return fileName.isEmpty ? "READ sed" : "READ \(fileName)"
        }

        return normalized
    }

    private func compactAppleScriptAction(from loweredCommand: String) -> String {
        if loweredCommand.contains("quit app") {
            return "APP quit"
        }
        if loweredCommand.contains("activate") || loweredCommand.contains("launch") {
            return "APP open"
        }
        return "APP osascript"
    }

    private func compactPythonAction(_ command: String) -> String {
        let parts = command.split(separator: " ", omittingEmptySubsequences: true)
        let script = parts.dropFirst().first { !$0.hasPrefix("-") }.map(String.init)
        let scriptName = script.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "python"

        if command.contains("/dev/cu.") || scriptName.lowercased().contains("serial") {
            return "SERIAL \(scriptName)"
        }

        return "PY \(scriptName)"
    }

    private func strippedShellPrefix(_ command: String) -> String {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let chained = command.components(separatedBy: "&&").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? command
        let parts = chained.split(separator: " ", omittingEmptySubsequences: true)
        let firstCommandIndex = parts.firstIndex { part in
            !part.contains("=") || part.hasPrefix("-")
        } ?? parts.startIndex

        return parts[firstCommandIndex...].joined(separator: " ")
    }

    private func firstShellWords<S: StringProtocol>(_ value: S, count: Int) -> String {
        value.split(separator: " ", omittingEmptySubsequences: true)
            .prefix(count)
            .joined(separator: " ")
    }

    private func firstSearchTerm(from value: String) -> String {
        let terms = value.split(separator: " ", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("-") }

        return terms.first.map(String.init) ?? "rg"
    }

    private func shouldCompactAsPath(_ value: String, toolName: String) -> Bool {
        let normalizedToolName = toolName.lowercased()
        if normalizedToolName == "bash" {
            return false
        }

        return !value.contains(" ") && value.contains("/")
    }

    private func waitingActionDetail(toolName: String, action: String?) -> String {
        if shouldUseAllowVerb(for: toolName) {
            if let action {
                return "ALLOW \(toolName) \(action)"
            }
            return "ALLOW \(toolName)"
        }

        if let action {
            return "APPROVE \(toolName) \(action)"
        }
        return "APPROVE \(toolName)"
    }

    private func shouldUseAllowVerb(for toolName: String) -> Bool {
        switch toolName.lowercased() {
        case "edit", "write", "multiedit", "read":
            true
        default:
            false
        }
    }
}
