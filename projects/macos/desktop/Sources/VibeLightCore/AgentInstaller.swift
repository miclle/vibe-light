import Foundation

public enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

public struct AgentInstallationStatus: Equatable, Sendable {
    public var agent: AgentKind
    public var isInstalled: Bool
    public var configURL: URL
    public var message: String

    public init(agent: AgentKind, isInstalled: Bool, configURL: URL, message: String) {
        self.agent = agent
        self.isInstalled = isInstalled
        self.configURL = configURL
        self.message = message
    }
}

public struct AgentInstaller {
    public static let managedMarker = "Managed by Vibe Light"

    public var homeDirectory: URL
    public var fileManager: FileManager

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func status(_ agent: AgentKind) throws -> AgentInstallationStatus {
        let configURL = primaryConfigURL(for: agent)
        let data = try? Data(contentsOf: configURL)
        let installed = data.flatMap { containsManagedHook(in: $0) } ?? false

        return AgentInstallationStatus(
            agent: agent,
            isInstalled: installed,
            configURL: configURL,
            message: installed ? "已安装 Vibe Light hook" : "未安装"
        )
    }

    public func install(_ agent: AgentKind, hookExecutableURL: URL) throws {
        switch agent {
        case .codex:
            try installCodex(hookExecutableURL: hookExecutableURL)
        case .claude:
            try installClaude(hookExecutableURL: hookExecutableURL)
        }
    }

    public func uninstall(_ agent: AgentKind) throws {
        let url = primaryConfigURL(for: agent)
        guard let data = try? Data(contentsOf: url) else {
            return
        }

        var root = try loadRootObject(from: data)
        root["hooks"] = cleanedHooksObject(from: root["hooks"])

        if let hooks = root["hooks"] as? [String: Any], hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        }

        if root.isEmpty {
            try? fileManager.removeItem(at: url)
        } else {
            try writeJSON(root, to: url)
        }
    }

    public func primaryConfigURL(for agent: AgentKind) -> URL {
        switch agent {
        case .codex:
            homeDirectory.appendingPathComponent(".codex/hooks.json")
        case .claude:
            homeDirectory.appendingPathComponent(".claude/settings.json")
        }
    }

    public func codexConfigURL() -> URL {
        homeDirectory.appendingPathComponent(".codex/config.toml")
    }

    private func installCodex(hookExecutableURL: URL) throws {
        let hooksURL = primaryConfigURL(for: .codex)
        let command = hookCommand(for: hookExecutableURL, source: .codex)
        try installHooks(
            at: hooksURL,
            events: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop"],
            command: command
        )
        try enableCodexHooksFeature()
    }

    private func installClaude(hookExecutableURL: URL) throws {
        let command = hookCommand(for: hookExecutableURL, source: .claude)
        try installHooks(
            at: primaryConfigURL(for: .claude),
            events: [
                "SessionStart",
                "UserPromptSubmit",
                "PreToolUse",
                "PostToolUse",
                "PermissionRequest",
                "PermissionDenied",
                "Stop",
                "StopFailure",
                "SessionEnd",
            ],
            command: command
        )
    }

    private func installHooks(at url: URL, events: [String], command: String) throws {
        var root = try existingRootObject(at: url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for event in events {
            let existingGroups = hooks[event] as? [Any] ?? []
            hooks[event] = cleanedGroups(from: existingGroups) + [managedGroup(command: command)]
        }

        root["hooks"] = hooks
        try writeJSON(root, to: url)
    }

    private func enableCodexHooksFeature() throws {
        let url = codexConfigURL()
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = codexConfigWithHooksEnabled(existing)
        guard updated != existing else { return }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private func codexConfigWithHooksEnabled(_ contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")

        if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            let nextSectionIndex = lines[(featuresIndex + 1)...].firstIndex { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            } ?? lines.count

            if let hooksIndex = lines[(featuresIndex + 1)..<nextSectionIndex].firstIndex(where: { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("hooks")
            }) {
                lines[hooksIndex] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: nextSectionIndex)
            }
            return lines.joined(separator: "\n")
        }

        if !lines.isEmpty, lines.last?.isEmpty == false {
            lines.append("")
        }
        lines.append("[features]")
        lines.append("hooks = true")
        return lines.joined(separator: "\n")
    }

    private func existingRootObject(at url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        return try loadRootObject(from: data)
    }

    private func loadRootObject(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func writeJSON(_ root: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func cleanedHooksObject(from value: Any?) -> [String: Any] {
        let hooks = value as? [String: Any] ?? [:]
        return hooks.reduce(into: [:]) { result, item in
            let groups = cleanedGroups(from: item.value as? [Any] ?? [])
            if !groups.isEmpty {
                result[item.key] = groups
            }
        }
    }

    private func cleanedGroups(from groups: [Any]) -> [[String: Any]] {
        groups.compactMap { group in
            guard var group = group as? [String: Any] else { return nil }
            let hooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = hooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else { return nil }
                return isManagedHook(hook) ? nil : hook
            }

            guard !filteredHooks.isEmpty else { return nil }
            group["hooks"] = filteredHooks
            return group
        }
    }

    private func managedGroup(command: String) -> [String: Any] {
        [
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "description": Self.managedMarker,
                ],
            ],
        ]
    }

    private func containsManagedHook(in data: Data) -> Bool {
        guard let root = try? loadRootObject(from: data),
              let hooks = root["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            let groups = value as? [Any] ?? []
            return groups.contains { group in
                guard let group = group as? [String: Any],
                      let hookEntries = group["hooks"] as? [Any] else {
                    return false
                }
                return hookEntries.contains { hook in
                    guard let hook = hook as? [String: Any] else { return false }
                    return isManagedHook(hook)
                }
            }
        }
    }

    private func isManagedHook(_ hook: [String: Any]) -> Bool {
        if hook["description"] as? String == Self.managedMarker {
            return true
        }
        let command = hook["command"] as? String ?? ""
        return command.contains("vibe-light-hook")
    }

    private func hookCommand(for url: URL, source: VibeSource) -> String {
        "\(shellQuote(url.path)) --source \(source.rawValue)"
    }
}

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
