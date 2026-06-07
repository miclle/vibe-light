import Foundation
import Testing
@testable import VibeLightCore

@Test func hookEventMappingProducesStableHardwareStates() {
    #expect(VibeHookEvent(source: .codex, kind: .sessionStart).displayState == .busy)
    #expect(VibeHookEvent(source: .claude, kind: .permissionRequest).displayState == .waiting)
    #expect(VibeHookEvent(source: .codex, kind: .stop).displayState == .success)
    #expect(VibeHookEvent(source: .claude, kind: .stopFailure).displayState == .error)
}

@Test func statusPacketEncodesProtocolJson() throws {
    let packet = StatusPacket(
        source: .codex,
        state: .busy,
        detail: "PreToolUse",
        timestamp: Date(timeIntervalSince1970: 1_780_300_800)
    )

    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["v"] as? Int == 1)
    #expect(object["source"] as? String == "codex")
    #expect(object["state"] as? String == "busy")
    #expect(object["detail"] as? String == "PreToolUse")
    #expect(object["ts"] as? Int64 == 1_780_300_800_000)
}

@Test func statusPacketKeepsDetailShortForBleWrite() throws {
    let packet = StatusPacket(
        source: .codex,
        state: .busy,
        detail: String(repeating: "正在执行命令", count: 30),
        timestamp: Date(timeIntervalSince1970: 1_780_300_800)
    )

    let detail = try #require(packet.detail)
    let data = try packet.encodedJSON()

    #expect(detail.utf8.count <= StatusPacket.maxDetailUTF8Bytes)
    #expect(String(data: Data(detail.utf8), encoding: .utf8) == detail)
    #expect(data.count < 256)
}

@Test func healthPacketDecodesFirmwareJson() throws {
    let data = """
    {"connected":true,"device":"VibeLight-S3","lastState":"busy","uptimeMs":12000,"v":1}
    """.data(using: .utf8)!

    let packet = try JSONDecoder().decode(HealthPacket.self, from: data)

    #expect(packet.v == 1)
    #expect(packet.device == "VibeLight-S3")
    #expect(packet.uptimeMs == 12_000)
    #expect(packet.connected)
    #expect(packet.lastState == .busy)
}

@Test func eventStoreKeepsMostRecentEventsFirstAndUpdatesCurrentState() {
    let store = EventStore(limit: 2)

    store.record(.init(source: .codex, kind: .sessionStart, detail: "started"))
    store.record(.init(source: .codex, kind: .permissionRequest, detail: "approval"))
    store.record(.init(source: .claude, kind: .stopFailure, detail: "failed"))

    #expect(store.events.map(\.detail) == ["failed", "approval"])
    #expect(store.currentState == .error)
    #expect(store.latestPacket?.source == .claude)
}

@Test func taskTrackerKeepsBusyWhenAnotherTaskStopsLater() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(taskID: "codex:task-b", source: .codex, kind: .stop, timestamp: base.addingTimeInterval(3), workspace: "api-specs"),
        .init(taskID: "codex:task-b", source: .codex, kind: .preToolUse, timestamp: base.addingTimeInterval(2), workspace: "api-specs"),
        .init(taskID: "codex:task-a", source: .codex, kind: .preToolUse, timestamp: base.addingTimeInterval(1), workspace: "vibe-light"),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(4))

    #expect(snapshot.state == .busy)
    #expect(snapshot.source == .codex)
    #expect(snapshot.detail == "1 running")
    #expect(snapshot.tasks.map(\.title) == ["vibe-light"])
    #expect(snapshot.statusPacket.state == .busy)
}

@Test func taskTrackerPrioritizesWaitingOverBusy() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(taskID: "codex:task-b", source: .codex, kind: .permissionRequest, timestamp: base.addingTimeInterval(3), workspace: "slideo"),
        .init(taskID: "codex:task-a", source: .codex, kind: .preToolUse, timestamp: base.addingTimeInterval(2), workspace: "vibe-light"),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(4))

    #expect(snapshot.state == .waiting)
    #expect(snapshot.detail == "1 running · 1 waiting")
    #expect(snapshot.tasks.map(\.title).prefix(2) == ["slideo", "vibe-light"])
}

@Test func hookPayloadDecoderExtractsStableTaskIdentity() throws {
    let data = """
    {
      "hook_event_name": "PreToolUse",
      "session_id": "session-123",
      "cwd": "/Users/miclle/github/miclle/vibe-light"
    }
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .codex).decode(data)

    #expect(event.taskID == "codex:session-123")
}

@Test func setupChecklistReportsReadyOnlyAfterRequiredSteps() {
    var checklist = SetupChecklist()

    #expect(checklist.isReady == false)
    #expect(checklist.completedCount == 0)

    checklist.mark(.installApp, as: .complete)
    checklist.mark(.installHooks, as: .complete)
    checklist.mark(.connectDevice, as: .complete)

    #expect(checklist.isReady)
    #expect(checklist.completedCount == 3)
}

@Test func hookPayloadDecoderAcceptsSimpleJsonPayload() throws {
    let data = """
    {"source":"codex","event":"PermissionRequest","detail":"approve shell command"}
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder().decode(data)

    #expect(event.source == .codex)
    #expect(event.kind == .permissionRequest)
    #expect(event.detail == "approve shell command")
    #expect(event.summary == "approve shell command")
}

@Test func hookPayloadDecoderUsesDefaultSourceWhenPayloadOmitsSource() throws {
    let data = """
    {"event":"Stop","detail":"done"}
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .claude).decode(data)

    #expect(event.source == .claude)
    #expect(event.kind == .stop)
}

@Test func hookPayloadDecoderExtractsCodexToolDetails() throws {
    let data = """
    {
      "hook_event_name": "PreToolUse",
      "cwd": "/Users/miclle/github/miclle/vibe-light",
      "tool_name": "Bash",
      "tool_input": {
        "command": "swift test --package-path projects/macos/desktop",
        "description": "Run macOS tests"
      }
    }
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .codex).decode(data)

    #expect(event.kind == .preToolUse)
    #expect(event.toolName == "Bash")
    #expect(event.workspace == "vibe-light")
    #expect(event.summary == "Run macOS tests")
    #expect(event.message == "swift test --package-path projects/macos/desktop")
    #expect(event.rawPayload == String(data: data, encoding: .utf8))
    #expect(PayloadFormatter.prettyPrintedJSON(event.rawPayload ?? "")?.contains("\n") == true)
    #expect(PayloadFormatter.prettyPrintedJSON(event.rawPayload ?? "")?.contains("  \"tool_name\"") == true)
}

@Test func hookPayloadDecoderExtractsClaudePermissionDetails() throws {
    let data = """
    {
      "hook_event_name": "PermissionRequest",
      "cwd": "/Users/miclle/github/miclle/vibe-light",
      "tool_name": "Edit",
      "message": "Claude wants to edit README.md",
      "tool_input": {
        "file_path": "/Users/miclle/github/miclle/vibe-light/README.md"
      }
    }
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .claude).decode(data)

    #expect(event.kind == .permissionRequest)
    #expect(event.toolName == "Edit")
    #expect(event.workspace == "vibe-light")
    #expect(event.summary == "Claude wants to edit README.md")
    #expect(event.message == "/Users/miclle/github/miclle/vibe-light/README.md")
}

@Test func eventLogAppendsAndReadsNewestFirst() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let log = EventLog(directory: directory)

    try log.append(.init(source: .codex, kind: .sessionStart, detail: "started"))
    try log.append(.init(source: .claude, kind: .stop, detail: "done"))

    let events = try log.readRecent(limit: 10)

    #expect(events.map(\.detail) == ["done", "started"])
}

@Test func eventLogPrunesOldEntriesAfterAppend() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let log = EventLog(directory: directory, retentionLimit: 3)

    for index in 0..<5 {
        try log.append(.init(source: .codex, kind: .preToolUse, detail: "event-\(index)"))
    }

    let text = try String(contentsOf: log.fileURL, encoding: .utf8)
    let lines = text.split(separator: "\n")
    let events = try log.readRecent(limit: 10)

    #expect(lines.count == 3)
    #expect(events.map(\.detail) == ["event-4", "event-3", "event-2"])
}

@Test func agentInstallerInstallsCodexHooksAndFeatureFlag() throws {
    let home = temporaryDirectory()
    let installer = AgentInstaller(homeDirectory: home)
    let hookURL = home.appendingPathComponent("bin/vibe-light-hook")

    try installer.install(.codex, hookExecutableURL: hookURL)

    let status = try installer.status(.codex)
    #expect(status.isInstalled)

    let hooksData = try Data(contentsOf: home.appendingPathComponent(".codex/hooks.json"))
    let hooksRoot = try #require(JSONSerialization.jsonObject(with: hooksData) as? [String: Any])
    let hooks = try #require(hooksRoot["hooks"] as? [String: Any])
    #expect(hooks.keys.contains("SessionStart"))
    #expect(hooks.keys.contains("PermissionRequest"))

    let config = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
    #expect(config.contains("[features]"))
    #expect(config.contains("hooks = true"))
}

@Test func agentInstallerCopiesHookToStableApplicationSupportPath() throws {
    let home = temporaryDirectory()
    let sourceDirectory = home.appendingPathComponent("build", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let sourceURL = sourceDirectory.appendingPathComponent("vibe-light-hook")
    try Data("hook".utf8).write(to: sourceURL)

    let installer = AgentInstaller(homeDirectory: home)
    let installedURL = try installer.prepareHookExecutable(from: sourceURL)

    #expect(installedURL == installer.stableHookExecutableURL())
    #expect(FileManager.default.fileExists(atPath: installedURL.path))

    try installer.install(.codex, hookExecutableURL: installedURL)

    let hooksData = try Data(contentsOf: home.appendingPathComponent(".codex/hooks.json"))
    let hooksRoot = try #require(JSONSerialization.jsonObject(with: hooksData) as? [String: Any])
    let hooks = try #require(hooksRoot["hooks"] as? [String: Any])
    let groups = try #require(hooks["SessionStart"] as? [[String: Any]])
    let entries = try #require(groups.first?["hooks"] as? [[String: Any]])
    let command = try #require(entries.first?["command"] as? String)

    #expect(command.contains(installedURL.path))
    #expect(!command.contains(sourceURL.path))
}

@Test func agentInstallerPreservesLegacyCodexHooksFeatureKey() throws {
    let home = temporaryDirectory()
    let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    try """
    [features]
    codex_hooks = false
    """.write(to: codexDirectory.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

    let installer = AgentInstaller(homeDirectory: home)
    let hookURL = home.appendingPathComponent("bin/vibe-light-hook")

    try installer.install(.codex, hookExecutableURL: hookURL)

    let config = try String(contentsOf: codexDirectory.appendingPathComponent("config.toml"), encoding: .utf8)
    let configLines = config.components(separatedBy: "\n")
    #expect(configLines.contains("codex_hooks = true"))
    #expect(!configLines.contains("hooks = true"))
}

@Test func agentInstallerPreservesOtherClaudeHooksWhenUninstalling() throws {
    let home = temporaryDirectory()
    let claudeDirectory = home.appendingPathComponent(".claude", isDirectory: true)
    try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
    let settingsURL = claudeDirectory.appendingPathComponent("settings.json")
    try """
    {
      "hooks": {
        "Stop": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "echo external"
              }
            ]
          }
        ]
      }
    }
    """.data(using: .utf8)!.write(to: settingsURL)

    let installer = AgentInstaller(homeDirectory: home)
    let hookURL = home.appendingPathComponent("bin/vibe-light-hook")

    try installer.install(.claude, hookExecutableURL: hookURL)
    try installer.uninstall(.claude)

    let data = try Data(contentsOf: settingsURL)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let hooks = try #require(root["hooks"] as? [String: Any])
    let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
    let stopHooks = try #require(stopGroups.first?["hooks"] as? [[String: Any]])

    #expect(stopHooks.count == 1)
    #expect(stopHooks.first?["command"] as? String == "echo external")
    #expect(try installer.status(.claude).isInstalled == false)
}

@Test func hardwareDeviceStoreTracksScanningAndConnectionState() {
    let store = HardwareDeviceStore()
    let device = HardwareDevice(id: "esp32", name: "VibeLight-S3", rssi: -48)

    store.startScanning()
    store.upsert(device)
    store.connect(device.id)

    #expect(store.isScanning == false)
    #expect(store.devices == [device])
    #expect(store.connectionState == .connected(device.id))
}

@Test func hardwareConnectionStateReportsActionAvailability() {
    #expect(HardwareConnectionState.connected("esp32").isConnected)
    #expect(!HardwareConnectionState.connected("esp32").isConnecting)
    #expect(HardwareConnectionState.connecting("esp32").isConnecting)
    #expect(!HardwareConnectionState.connecting("esp32").isConnected)
    #expect(!HardwareConnectionState.disconnected.isConnected)
    #expect(!HardwareConnectionState.scanning.isConnecting)
}

@Test func vibeLightPreferencesPersistHardwareDefaults() throws {
    let suiteName = "VibeLightPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let preferences = VibeLightPreferences(defaults: defaults)
    #expect(preferences.autoConnectDevice)
    #expect(preferences.selectedManualState == .idle)

    preferences.autoConnectDevice = false
    preferences.selectedManualState = .waiting

    let reloaded = VibeLightPreferences(defaults: defaults)
    #expect(!reloaded.autoConnectDevice)
    #expect(reloaded.selectedManualState == .waiting)
}

private func temporaryDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
