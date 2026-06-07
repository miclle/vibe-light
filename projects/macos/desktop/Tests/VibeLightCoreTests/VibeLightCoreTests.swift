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

@Test func eventStoreKeepsMostRecentEventsFirstAndUpdatesCurrentState() {
    let store = EventStore(limit: 2)

    store.record(.init(source: .codex, kind: .sessionStart, detail: "started"))
    store.record(.init(source: .codex, kind: .permissionRequest, detail: "approval"))
    store.record(.init(source: .claude, kind: .stopFailure, detail: "failed"))

    #expect(store.events.map(\.detail) == ["failed", "approval"])
    #expect(store.currentState == .error)
    #expect(store.latestPacket?.source == .claude)
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

private func temporaryDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
