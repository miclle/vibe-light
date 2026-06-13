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
    {"animationTick":42,"backlightOn":true,"connected":true,"device":"VibeLight-S3","freeHeapBytes":4218880,"lastParseError":"invalid JSON","lastState":"busy","minFreeHeapBytes":3981312,"uptimeMs":12000,"v":1}
    """.data(using: .utf8)!

    let packet = try JSONDecoder().decode(HealthPacket.self, from: data)

    #expect(packet.v == 1)
    #expect(packet.device == "VibeLight-S3")
    #expect(packet.uptimeMs == 12_000)
    #expect(packet.connected)
    #expect(packet.lastState == .busy)
    #expect(packet.freeHeapBytes == 4_218_880)
    #expect(packet.minFreeHeapBytes == 3_981_312)
    #expect(packet.animationTick == 42)
    #expect(packet.backlightOn == true)
    #expect(packet.lastParseError == "invalid JSON")
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
    #expect(snapshot.tasks.first?.identityKind == .explicit)
    #expect(snapshot.tasks.first?.inclusionReason == "active busy task from session id")
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
    #expect(snapshot.tasks.first?.identityKind == .explicit)
}

@Test func displaySnapshotBuildsV2StatusPacketWithTaskList() throws {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(taskID: "codex:task-c", source: .codex, kind: .stopFailure, timestamp: base.addingTimeInterval(3), summary: "build failed", workspace: "firmware"),
        .init(taskID: "claude:task-b", source: .claude, kind: .permissionRequest, timestamp: base.addingTimeInterval(2), summary: "approve edit", workspace: "docs"),
        .init(taskID: "codex:task-a", source: .codex, kind: .preToolUse, timestamp: base.addingTimeInterval(1), summary: "implement v2", workspace: "vibe-light"),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(4))
    let packet = snapshot.statusPacket
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(packet.v == 2)
    #expect(object["activeCount"] as? Int == 2)
    #expect(object["waitingCount"] as? Int == 1)
    #expect(object["errorCount"] as? Int == 1)
    #expect(tasks.map { $0["title"] as? String } == ["docs", "vibe-light"])
    #expect(tasks.map { $0["state"] as? String } == ["waiting", "busy"])
    #expect(snapshot.tasks.map(\.lastDetail) == ["approve edit", "implement v2"])
    #expect(tasks.map { $0["detail"] as? String } == ["approve edit", "implement v2"])
    #expect(tasks.map { $0["updatedAt"] as? Int64 } == [1_780_300_802_000, 1_780_300_801_000])
    #expect(object["ts"] as? Int64 == 1_780_300_804_000)
    #expect(data.count < 768)
}

@Test func taskTrackerSummarizesLastResultWhenNoTasksAreActive() throws {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .stopFailure,
            timestamp: base,
            summary: "build failed",
            workspace: "firmware"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))
    let packet = snapshot.statusPacket
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(snapshot.state == .idle)
    #expect(snapshot.detail == "LAST ERR build failed")
    #expect(snapshot.tasks.isEmpty)
    #expect(tasks.isEmpty)
    #expect(object["detail"] as? String == "LAST ERR build failed")
}

@Test func taskTrackerExpiresLastResultAfterStaleWindow() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker(staleAfter: 60)
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .stop,
            timestamp: base,
            summary: "make quick passed",
            workspace: "vibe-light"
        ),
    ]

    let recent = tracker.snapshot(from: events, now: base.addingTimeInterval(1))
    let expired = tracker.snapshot(from: events, now: base.addingTimeInterval(61))

    #expect(recent.detail == "LAST OK make quick passed")
    #expect(expired.state == .idle)
    #expect(expired.detail == "no active tasks")
    #expect(expired.tasks.isEmpty)
}

@Test func taskTrackerSummarizesLastToolResultFromCompactAction() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .stop,
            timestamp: base.addingTimeInterval(1),
            summary: "verification passed",
            message: "make quick",
            toolName: "Bash",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(2))

    #expect(snapshot.state == .idle)
    #expect(snapshot.detail == "LAST OK Bash / TEST make quick")
    #expect(snapshot.tasks.isEmpty)
}

@Test func taskTrackerShowsCurrentToolActionInTaskDetail() throws {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .preToolUse,
            timestamp: base,
            summary: "Run quick verification",
            message: "make quick",
            toolName: "Bash",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))
    let packet = snapshot.statusPacket
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(snapshot.tasks.first?.lastDetail == "Bash / TEST make quick")
    #expect(tasks.first?["detail"] as? String == "Bash / TEST make quick")
}

@Test func taskDetailFormatterCompactsToolActionsWithoutTaskTrackerState() {
    let formatter = TaskDetailFormatter()

    #expect(formatter.detail(toolName: "Bash", message: "make quick", state: .busy, fallback: "PreToolUse") == "Bash / TEST make quick")
    #expect(formatter.detail(toolName: "Edit", message: "/Users/miclle/github/miclle/vibe-light/README.md", state: .busy, fallback: "PreToolUse") == "Edit / README.md")
    #expect(formatter.detail(toolName: "Bash", message: "make verify", state: .waiting, fallback: "PermissionRequest") == "APPROVE Bash TEST make verify")
    #expect(formatter.detail(toolName: "Edit", message: "/Users/miclle/github/miclle/vibe-light/TODO.md", state: .waiting, fallback: "PermissionRequest") == "ALLOW Edit TODO.md")
}

@Test func taskTrackerCompactsToolFilePathsInTaskDetail() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "claude:task-a",
            source: .claude,
            kind: .preToolUse,
            timestamp: base,
            summary: "Claude wants to edit README.md",
            message: "/Users/miclle/github/miclle/vibe-light/README.md",
            toolName: "Edit",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))

    #expect(snapshot.tasks.first?.lastDetail == "Edit / README.md")
}

@Test func taskTrackerShowsApprovalActionForWaitingToolTasks() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .permissionRequest,
            timestamp: base,
            summary: "approve shell command",
            message: "make verify",
            toolName: "Bash",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))

    #expect(snapshot.state == .waiting)
    #expect(snapshot.tasks.first?.lastDetail == "APPROVE Bash TEST make verify")
}

@Test func taskTrackerShowsApprovalActionForWaitingToolTasksWithoutMessage() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .permissionRequest,
            timestamp: base,
            summary: "approve shell command",
            toolName: "Bash",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))

    #expect(snapshot.state == .waiting)
    #expect(snapshot.tasks.first?.lastDetail == "APPROVE Bash")
}

@Test func taskTrackerCompactsShellCommandsWithEnvironmentAssignments() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .preToolUse,
            timestamp: base,
            message: "ESP32_PORT=/dev/cu.usbmodem2101 make esp32-flash",
            toolName: "Bash",
            workspace: "vibe-light"
        ),
        .init(
            taskID: "codex:task-b",
            source: .codex,
            kind: .preToolUse,
            timestamp: base.addingTimeInterval(1),
            message: "rg -n \"StatusPacket\" projects/macos",
            toolName: "Bash",
            workspace: "docs"
        ),
    ]

    let snapshot = tracker.snapshot(from: Array(events.reversed()), now: base.addingTimeInterval(2))

    #expect(snapshot.tasks.map(\.lastDetail) == [
        "Bash / SEARCH \"StatusPacket\"",
        "Bash / FLASH make esp32-flash"
    ])
}

@Test func taskTrackerCompactsCommonRuntimeAndDeviceCommands() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .preToolUse,
            timestamp: base,
            message: "python3 projects/esp32/tools/read_serial.py --port /dev/cu.usbmodem2101 --seconds 300",
            toolName: "Bash",
            workspace: "serial"
        ),
        .init(
            taskID: "codex:task-b",
            source: .codex,
            kind: .preToolUse,
            timestamp: base.addingTimeInterval(1),
            message: "osascript -e 'quit app \"VibeLightApp\"'",
            toolName: "Bash",
            workspace: "desktop"
        ),
        .init(
            taskID: "codex:task-c",
            source: .codex,
            kind: .preToolUse,
            timestamp: base.addingTimeInterval(2),
            message: "idf.py -C projects/esp32 build",
            toolName: "Bash",
            workspace: "firmware"
        ),
    ]

    let snapshot = tracker.snapshot(from: Array(events.reversed()), now: base.addingTimeInterval(3))

    #expect(snapshot.tasks.map(\.lastDetail) == [
        "Bash / BUILD idf.py",
        "Bash / APP quit",
        "Bash / SERIAL read_serial.py",
    ])
}

@Test func taskTrackerShowsAllowActionForWaitingFileTools() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "claude:task-a",
            source: .claude,
            kind: .permissionRequest,
            timestamp: base,
            summary: "Claude wants to edit README.md",
            message: "/Users/miclle/github/miclle/vibe-light/README.md",
            toolName: "Edit",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))

    #expect(snapshot.state == .waiting)
    #expect(snapshot.tasks.first?.lastDetail == "ALLOW Edit README.md")
}

@Test func hookPayloadDecoderExtractsCodexUsageFromTranscriptTokenCount() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let transcriptURL = directory.appendingPathComponent("session.jsonl")
    try """
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000},"model_context_window":10000},"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1781014908},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1781445567}}}}
    """.write(to: transcriptURL, atomically: true, encoding: .utf8)

    let data = """
    {
      "hook_event_name": "PreToolUse",
      "session_id": "session-123",
      "transcript_path": "\(transcriptURL.path)",
      "cwd": "/Users/miclle/github/miclle/vibe-light"
    }
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .codex).decode(data)
    let usage = try #require(event.codexUsage)

    #expect(usage.fiveHourRemainingPercent == 88)
    #expect(usage.weeklyRemainingPercent == 60)
    #expect(usage.contextUsedPercent == 10)
    #expect(usage.contextUsedTokens == 1000)
    #expect(usage.contextWindowTokens == 10000)
    #expect(usage.fiveHourResetAtMilliseconds == 1_781_014_908_000)
    #expect(usage.weeklyResetAtMilliseconds == 1_781_445_567_000)
}

@Test func hookPayloadDecoderUsesLastInputTokensForContextUsed() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let transcriptURL = directory.appendingPathComponent("session.jsonl")
    try """
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1000000},"last_token_usage":{"input_tokens":2000},"model_context_window":10000},"rate_limits":{"primary":{"used_percent":5,"window_minutes":300},"secondary":{"used_percent":21,"window_minutes":10080}}}}
    """.write(to: transcriptURL, atomically: true, encoding: .utf8)

    let data = """
    {
      "hook_event_name": "PreToolUse",
      "session_id": "session-123",
      "transcript_path": "\(transcriptURL.path)",
      "cwd": "/Users/miclle/github/miclle/vibe-light"
    }
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .codex).decode(data)

    #expect(event.codexUsage?.contextUsedPercent == 20)
    #expect(event.codexUsage?.contextUsedTokens == 2000)
    #expect(event.codexUsage?.contextWindowTokens == 10000)
}

@Test func codexUsageReaderFindsLatestTokenCountNearTranscriptTail() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let transcriptURL = directory.appendingPathComponent("session.jsonl")
    let filler = (0..<1_200)
        .map { #"{"type":"event_msg","payload":{"type":"other","index":\#($0),"text":"正在处理一段较长的输出，保持 transcript 体积接近真实会话。"}}"# }
        .joined(separator: "\n")
    try """
    {"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":4200},"model_context_window":12000},"rate_limits":{"primary":{"used_percent":25,"window_minutes":300},"secondary":{"used_percent":50,"window_minutes":10080}}}}
    \(filler)
    """.write(to: transcriptURL, atomically: true, encoding: .utf8)

    let usage = try #require(CodexUsageReader().readLatest(from: transcriptURL))

    #expect(usage.fiveHourRemainingPercent == 75)
    #expect(usage.weeklyRemainingPercent == 50)
    #expect(usage.contextUsedPercent == 35)
    #expect(usage.contextUsedTokens == 4200)
    #expect(usage.contextWindowTokens == 12000)
}

@Test func displaySnapshotAddsUsageToStatusPacketAndTasks() throws {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:task-a",
            source: .codex,
            kind: .preToolUse,
            timestamp: base,
            summary: "implement usage",
            workspace: "vibe-light",
            codexUsage: CodexUsage(
                fiveHourRemainingPercent: 88,
                weeklyRemainingPercent: 60,
                contextUsedPercent: 90,
                contextUsedTokens: 10_800,
                contextWindowTokens: 12_000,
                fiveHourResetAtMilliseconds: 1_781_014_908_000,
                weeklyResetAtMilliseconds: 1_781_445_567_000
            )
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))
    let packet = snapshot.statusPacket
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let usage = try #require(object["usage"] as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(usage["codex5hRemainingPercent"] as? Int == 88)
    #expect(usage["codex7dRemainingPercent"] as? Int == 60)
    #expect(usage["codex5hResetAt"] as? Int64 == 1_781_014_908_000)
    #expect(usage["codex7dResetAt"] as? Int64 == 1_781_445_567_000)
    #expect(tasks.first?["contextUsedPercent"] as? Int == 90)
    #expect(tasks.first?["contextUsedTokens"] as? Int == 10_800)
    #expect(tasks.first?["contextWindowTokens"] as? Int == 12_000)
}

@Test func displaySnapshotBackfillsUsageFromStoredRawPayloadTranscript() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let transcriptURL = directory.appendingPathComponent("session.jsonl")
    try """
    {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":2500},"model_context_window":10000},"rate_limits":{"primary":{"used_percent":5,"window_minutes":300},"secondary":{"used_percent":21,"window_minutes":10080}}}}
    """.write(to: transcriptURL, atomically: true, encoding: .utf8)

    let rawPayload = """
    {"session_id":"session-123","transcript_path":"\(transcriptURL.path)","cwd":"/Users/miclle/github/miclle/vibe-light","hook_event_name":"UserPromptSubmit"}
    """
    let event = VibeHookEvent(
        taskID: "codex:session-123",
        source: .codex,
        kind: .userPromptSubmit,
        timestamp: Date(timeIntervalSince1970: 1_780_300_800),
        summary: "implement usage",
        workspace: "vibe-light",
        rawPayload: rawPayload
    )

    let packet = TaskTracker().snapshot(
        from: [event],
        now: Date(timeIntervalSince1970: 1_780_300_801)
    ).statusPacket
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let usage = try #require(object["usage"] as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(usage["codex5hRemainingPercent"] as? Int == 95)
    #expect(usage["codex7dRemainingPercent"] as? Int == 79)
    #expect(tasks.first?["contextUsedPercent"] as? Int == 25)
}

@Test func codexUsageDecodesLegacyContextRemainingPercentAsUsedPercent() throws {
    let data = """
    {
      "fiveHourRemainingPercent": 88,
      "weeklyRemainingPercent": 60,
      "contextRemainingPercent": 75
    }
    """.data(using: .utf8)!

    let usage = try JSONDecoder().decode(CodexUsage.self, from: data)

    #expect(usage.contextUsedPercent == 25)
}

@Test func statusPacketKeepsChineseTaskDetails() throws {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(taskID: "codex:task-a", source: .codex, kind: .userPromptSubmit, timestamp: base, summary: "你来验证下", workspace: "vibe-light"),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(1))
    let packet = snapshot.statusPacket
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(snapshot.tasks.first?.lastDetail == "你来验证下")
    #expect(tasks.first?["detail"] as? String == "你来验证下")
}

@Test func statusPacketNormalizesUnsupportedTerminalGlyphsForHardware() throws {
    let task = StatusTask(
        title: "🧪 vibe-light",
        state: .busy,
        source: .codex,
        detail: "⎿  CODE REVIEW GUIDEL..."
    )
    let packet = StatusPacket(
        source: .codex,
        state: .busy,
        detail: "1 running · 1 waiting",
        tasks: [task]
    )
    let data = try packet.encodedJSON()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(packet.detail == "1 running · 1 waiting")
    #expect(tasks.first?["title"] as? String == "vibe-light")
    #expect(tasks.first?["detail"] as? String == "CODE REVIEW GUIDEL...")
}

@Test func statusPacketTruncatesTaskDetailsAtUtf8Boundaries() throws {
    let task = StatusTask(title: "firmware", state: .busy, source: .codex, detail: "修复 ESP32 detail 展示")

    #expect(task.detail == "修复 ESP32 detail 展示")
    #expect((task.detail ?? "").utf8.count <= StatusPacket.maxTaskDetailUTF8Bytes)
}

@Test func statusPacketFallsBackToV1WhenV2ExceedsBleWriteLength() throws {
    let packet = StatusPacket(
        v: 2,
        source: .codex,
        state: .busy,
        detail: "5 running",
        timestamp: Date(timeIntervalSince1970: 1_780_300_800),
        activeCount: 5,
        waitingCount: 0,
        errorCount: 0,
        tasks: (0..<5).map { index in
            StatusTask(
                title: "workspace-\(index)-with-long-name",
                state: .busy,
                source: .codex,
                detail: "running task \(index) with extra detail"
            )
        }
    )

    let fullData = try packet.encodedJSON()
    let constrainedData = try packet.encodedJSON(maximumWriteLength: 180)
    let object = try #require(JSONSerialization.jsonObject(with: constrainedData) as? [String: Any])

    #expect(fullData.count > 180)
    #expect(constrainedData.count <= 180)
    #expect(object["v"] as? Int == 1)
    #expect(object["tasks"] == nil)
    #expect(object["activeCount"] == nil)
}

@Test func statusPacketCompactsV2BeforeFallingBackToV1() throws {
    let packet = StatusPacket(
        v: 2,
        source: .codex,
        state: .busy,
        detail: "5 running",
        timestamp: Date(timeIntervalSince1970: 1_780_300_800),
        activeCount: 5,
        waitingCount: 0,
        errorCount: 0,
        tasks: (0..<5).map { index in
            StatusTask(
                title: "workspace-\(index)-with-long-name",
                state: .busy,
                source: .codex,
                detail: "running task \(index) with extra detail",
                contextUsedPercent: 70 + index
            )
        },
        usage: StatusUsage(codex5hRemainingPercent: 88, codex7dRemainingPercent: 60)
    )

    let fullData = try packet.encodedJSON()
    let constrainedData = try packet.encodedJSON(maximumWriteLength: 512)
    let object = try #require(JSONSerialization.jsonObject(with: constrainedData) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])
    let usage = try #require(object["usage"] as? [String: Any])

    #expect(fullData.count > 512)
    #expect(constrainedData.count <= 512)
    #expect(object["v"] as? Int == 2)
    #expect(usage["codex5hRemainingPercent"] as? Int == 88)
    #expect(usage["codex7dRemainingPercent"] as? Int == 60)
    #expect(tasks.count == 5)
    #expect(tasks.map { $0["title"] as? String } == (0..<5).map { "workspace-\($0)-with-long-name" })
}

@Test func statusPacketCompactorOwnsBleLengthFallbackStrategy() throws {
    let packet = StatusPacket(
        v: 2,
        source: .codex,
        state: .busy,
        detail: "5 running",
        timestamp: Date(timeIntervalSince1970: 1_780_300_800),
        activeCount: 5,
        waitingCount: 0,
        errorCount: 0,
        tasks: (0..<5).map { index in
            StatusTask(
                title: "workspace-\(index)-with-long-name",
                state: .busy,
                source: .codex,
                detail: "running task \(index) with extra detail",
                contextUsedPercent: 70 + index
            )
        },
        usage: StatusUsage(codex5hRemainingPercent: 88, codex7dRemainingPercent: 60)
    )

    let constrainedData = try StatusPacketCompactor().encodedJSON(for: packet, maximumWriteLength: 512)
    let object = try #require(JSONSerialization.jsonObject(with: constrainedData) as? [String: Any])

    #expect(constrainedData.count <= 512)
    #expect(object["v"] as? Int == 2)
    #expect(object["usage"] != nil)
    #expect(object["tasks"] != nil)
}

@Test func statusPacketPreservesTaskDetailsWhenCompactingV2ToBleLength() throws {
    let packet = StatusPacket(
        v: 2,
        source: .codex,
        state: .busy,
        detail: "3 running",
        timestamp: Date(timeIntervalSince1970: 1_780_300_800),
        activeCount: 3,
        waitingCount: 0,
        errorCount: 0,
        tasks: [
            StatusTask(
                title: "vibe-light",
                state: .busy,
                source: .codex,
                detail: "Bash / make quick",
                contextUsedPercent: 68,
                updatedAt: Date(timeIntervalSince1970: 1_780_300_782)
            ),
            StatusTask(
                title: "slideo",
                state: .busy,
                source: .codex,
                detail: "Edit / App.tsx",
                contextUsedPercent: 42,
                updatedAt: Date(timeIntervalSince1970: 1_780_300_762)
            ),
            StatusTask(
                title: "gitwikitree",
                state: .busy,
                source: .codex,
                detail: "UserPromptSubmit",
                contextUsedPercent: 25,
                updatedAt: Date(timeIntervalSince1970: 1_780_300_721)
            ),
        ],
        usage: StatusUsage(
            codex5hRemainingPercent: 99,
            codex7dRemainingPercent: 68,
            codex5hResetAt: 1_780_304_800_000,
            codex7dResetAt: 1_780_905_600_000
        )
    )

    let fullData = try packet.encodedJSON()
    let constrainedData = try packet.encodedJSON(maximumWriteLength: 512)
    let object = try #require(JSONSerialization.jsonObject(with: constrainedData) as? [String: Any])
    let tasks = try #require(object["tasks"] as? [[String: Any]])

    #expect(fullData.count > 512)
    #expect(constrainedData.count <= 512)
    #expect(object["v"] as? Int == 2)
    #expect(tasks.count == 3)
    #expect(tasks.compactMap { $0["detail"] as? String }.count == 3)
}

@Test func hardwareDemoPacketsProvideBoundedV2TaskScenarios() throws {
    let scenarios = HardwareDemoPacketScenario.allCases

    #expect(scenarios.map(\.id) == ["one-running", "mixed-waiting", "error-busy", "five-tasks", "ctx-color", "idle"])

    for scenario in scenarios {
        let packet = scenario.packet(timestamp: Date(timeIntervalSince1970: 1_780_300_800))
        let data = try packet.encodedJSON(maximumWriteLength: 512)

        #expect(packet.v == 2)
        #expect((packet.tasks ?? []).count <= 5)
        #expect(data.count <= 512)
    }
}

@Test func hardwareDemoPacketIncludesContextColorScenario() {
    let packet = HardwareDemoPacketScenario.ctxColor.packet(timestamp: Date(timeIntervalSince1970: 1_780_300_800))
    let tasks = packet.tasks ?? []

    #expect(packet.state == .busy)
    #expect(packet.detail == "CTX color check")
    #expect(packet.activeCount == 2)
    #expect(tasks.map(\.title) == ["ctx-warning", "ctx-critical"])
    #expect(tasks.map(\.contextUsedPercent) == [82, 92])
    #expect(tasks.map(\.contextUsedTokens) == [9_840, 11_040])
    #expect(tasks.map(\.contextWindowTokens) == [12_000, 12_000])
}

@Test func hardwareDemoPacketsExposeUsefulScreenStates() {
    let mixed = HardwareDemoPacketScenario.mixedWaiting.packet(timestamp: Date(timeIntervalSince1970: 1_780_300_800))
    let error = HardwareDemoPacketScenario.errorBusy.packet(timestamp: Date(timeIntervalSince1970: 1_780_300_800))
    let idle = HardwareDemoPacketScenario.idle.packet(timestamp: Date(timeIntervalSince1970: 1_780_300_800))

    #expect(mixed.state == .waiting)
    #expect(mixed.activeCount == 3)
    #expect(mixed.waitingCount == 1)
    #expect(mixed.tasks?.map(\.state) == [.waiting, .busy, .busy])

    #expect(error.state == .error)
    #expect(error.errorCount == 1)
    #expect(error.tasks?.map(\.state) == [.error, .busy])

    #expect(idle.state == .idle)
    #expect(idle.activeCount == 0)
    #expect(idle.tasks?.isEmpty == true)
}

@Test func hardwareDemoPacketHoldSuppressesLatestStatusForwardingTemporarily() {
    let start = Date(timeIntervalSince1970: 1_780_300_800)
    var hold = HardwareDemoPacketHold()

    #expect(hold.allowsLatestPacketForward(at: start))

    hold.start(at: start)

    #expect(!hold.allowsLatestPacketForward(at: start.addingTimeInterval(14.9)))
    #expect(hold.allowsLatestPacketForward(at: start.addingTimeInterval(15)))
}

@Test func taskTrackerIgnoresCodexMemoryWritingAgent() {
    let base = Date(timeIntervalSince1970: 1_780_300_800)
    let tracker = TaskTracker()
    let events: [VibeHookEvent] = [
        .init(
            taskID: "codex:memory",
            source: .codex,
            kind: .userPromptSubmit,
            timestamp: base.addingTimeInterval(2),
            summary: "## Memory Writing Agent: Phase 2 (Consolidation)",
            workspace: "memories"
        ),
        .init(
            taskID: "codex:vibe-light",
            source: .codex,
            kind: .userPromptSubmit,
            timestamp: base.addingTimeInterval(1),
            summary: "fix task counts",
            workspace: "vibe-light"
        ),
    ]

    let snapshot = tracker.snapshot(from: events, now: base.addingTimeInterval(3))

    #expect(snapshot.detail == "1 running")
    #expect(snapshot.tasks.map(\.title) == ["vibe-light"])
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

@Test func hookPayloadDecoderLeavesFallbackIdentityToTaskTracker() throws {
    let data = """
    {
      "hook_event_name": "PreToolUse",
      "cwd": "/Users/miclle/github/miclle/vibe-light"
    }
    """.data(using: .utf8)!

    let event = try HookPayloadDecoder(defaultSource: .codex).decode(data)
    let snapshot = TaskTracker().snapshot(from: [event])

    #expect(event.taskID == nil)
    #expect(snapshot.tasks.first?.identityKind == .workspace)
    #expect(snapshot.tasks.first?.inclusionReason == "active busy task from workspace fallback")
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

@Test func eventLogReadsRecentEventsFromLargeLogTail() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let log = EventLog(directory: directory, retentionLimit: 2_000)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let lines = try (0..<1_200).map { index in
        let event = VibeHookEvent(
            source: .codex,
            kind: .preToolUse,
            detail: "event-\(index)-正在处理较长输出"
        )
        return String(data: try encoder.encode(event), encoding: .utf8)!
    }.joined(separator: "\n") + "\n"
    try lines.write(to: log.fileURL, atomically: true, encoding: .utf8)

    let events = try log.readRecent(limit: 3)

    #expect(events.map(\.detail) == [
        "event-1199-正在处理较长输出",
        "event-1198-正在处理较长输出",
        "event-1197-正在处理较长输出",
    ])
}

@Test func eventLogSerializesConcurrentAppends() async throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let log = EventLog(directory: directory, retentionLimit: 60)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<40 {
            group.addTask {
                try log.append(.init(source: .codex, kind: .preToolUse, detail: "event-\(index)"))
            }
        }
        try await group.waitForAll()
    }

    let events = try log.readRecent(limit: 100)

    #expect(events.count == 40)
    #expect(Set(events.map(\.detail)).count == 40)
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
    #expect(hooks.keys.contains("PreToolUse"))
    #expect(hooks.keys.contains("PostToolUse"))

    let config = try String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8)
    #expect(config.contains("[features]"))
    #expect(config.contains("hooks = true"))
}

@Test func agentInstallerReportsIncompleteCodexToolHooksAsNeedsUpdate() throws {
    let home = temporaryDirectory()
    let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    try """
    {
      "hooks": {
        "SessionStart": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "vibe-light-hook --source codex",
                "description": "Managed by Vibe Light"
              }
            ]
          }
        ],
        "Stop": [
          {
            "hooks": [
              {
                "type": "command",
                "command": "vibe-light-hook --source codex",
                "description": "Managed by Vibe Light"
              }
            ]
          }
        ]
      }
    }
    """.data(using: .utf8)!.write(to: codexDirectory.appendingPathComponent("hooks.json"))

    let installer = AgentInstaller(homeDirectory: home)
    let status = try installer.status(.codex)

    #expect(status.isInstalled == false)
    #expect(status.message == "需要更新 Vibe Light hook")
}

@Test func agentInstallerInstallsCodexToolHooksWithoutRemovingUserMatchers() throws {
    let home = temporaryDirectory()
    let codexDirectory = home.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
    let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
    try """
    {
      "hooks": {
        "PreToolUse": [
          {
            "matcher": "Edit|Write",
            "hooks": [
              {
                "type": "command",
                "command": "protect-files"
              }
            ]
          }
        ]
      }
    }
    """.data(using: .utf8)!.write(to: hooksURL)

    let installer = AgentInstaller(homeDirectory: home)
    let hookURL = home.appendingPathComponent("bin/vibe-light-hook")

    try installer.install(.codex, hookExecutableURL: hookURL)

    let hooksData = try Data(contentsOf: hooksURL)
    let hooksRoot = try #require(JSONSerialization.jsonObject(with: hooksData) as? [String: Any])
    let hooks = try #require(hooksRoot["hooks"] as? [String: Any])
    let preToolGroups = try #require(hooks["PreToolUse"] as? [[String: Any]])
    let postToolGroups = try #require(hooks["PostToolUse"] as? [[String: Any]])

    #expect(preToolGroups.count == 2)
    #expect(preToolGroups.first?["matcher"] as? String == "Edit|Write")
    #expect(postToolGroups.count == 1)

    let managedPreHooks = try #require(preToolGroups.last?["hooks"] as? [[String: Any]])
    let managedPostHooks = try #require(postToolGroups.first?["hooks"] as? [[String: Any]])
    #expect((managedPreHooks.first?["command"] as? String)?.contains("vibe-light-hook") == true)
    #expect((managedPostHooks.first?["command"] as? String)?.contains("vibe-light-hook") == true)
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

@Test func hardwareDeviceStoreCanClearStaleDevicesWhenStartingFreshScan() {
    let store = HardwareDeviceStore()
    let staleDevice = HardwareDevice(id: "old-esp32", name: "VibeLight-S3", rssi: -44)

    store.upsert(staleDevice)
    store.startScanning(clearDevices: true)

    #expect(store.isScanning)
    #expect(store.devices.isEmpty)
    #expect(store.connectionState == .scanning)
}

@Test func hardwareConnectionStateReportsActionAvailability() {
    #expect(HardwareConnectionState.connected("esp32").isConnected)
    #expect(!HardwareConnectionState.connected("esp32").isConnecting)
    #expect(HardwareConnectionState.connecting("esp32").isConnecting)
    #expect(!HardwareConnectionState.connecting("esp32").isConnected)
    #expect(!HardwareConnectionState.disconnected.isConnected)
    #expect(!HardwareConnectionState.scanning.isConnecting)
}

@Test func hardwareReconnectPolicyRestartsAutoConnectAfterUnexpectedDisconnect() {
    let policy = HardwareReconnectPolicy(autoConnectEnabled: true)

    #expect(policy.action(after: .unexpectedDisconnect) == .scanAndAutoConnectFirstDevice)
    #expect(policy.action(after: .connectFailure) == .scanAndAutoConnectFirstDevice)
}

@Test func hardwareReconnectPolicyDoesNotRecoverManualDisconnectsOrDisabledAutoConnect() {
    let enabled = HardwareReconnectPolicy(autoConnectEnabled: true)
    let disabled = HardwareReconnectPolicy(autoConnectEnabled: false)

    #expect(enabled.action(after: .manualDisconnect) == .none)
    #expect(disabled.action(after: .unexpectedDisconnect) == .none)
    #expect(disabled.action(after: .connectFailure) == .none)
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

@Test func firmwareBundleManifestDecodesFlashFilesInOffsetOrder() throws {
    let data = """
    {
      "version": "0.3.0",
      "buildCommit": "abc1234",
      "targetChip": "esp32s3",
      "targetHardware": "Waveshare ESP32-S3-LCD-3.16",
      "flashMode": "dio",
      "flashFreq": "80m",
      "flashSize": "16MB",
      "minimumDesktopVersion": "0.3.0",
      "files": [
        {"offset": "0x10000", "path": "vibe_light_esp32.bin", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
        {"offset": "0x0", "path": "bootloader.bin", "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
        {"offset": "0x8000", "path": "partition-table.bin", "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}
      ]
    }
    """.data(using: .utf8)!

    let manifest = try JSONDecoder().decode(FirmwareBundleManifest.self, from: data)

    #expect(manifest.targetChip == "esp32s3")
    #expect(manifest.flashFiles.map(\.offset) == ["0x0", "0x8000", "0x10000"])
    #expect(manifest.flashFiles.map(\.path) == ["bootloader.bin", "partition-table.bin", "vibe_light_esp32.bin"])
}

@Test func firmwareBundleValidatorVerifiesChecksumsAndBuildsWriteFlashArguments() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bootloader = directory.appendingPathComponent("bootloader.bin")
    let partition = directory.appendingPathComponent("partition-table.bin")
    let app = directory.appendingPathComponent("vibe_light_esp32.bin")
    try Data("boot".utf8).write(to: bootloader)
    try Data("partition".utf8).write(to: partition)
    try Data("app".utf8).write(to: app)

    let manifest = FirmwareBundleManifest(
        version: "0.3.0",
        buildCommit: "abc1234",
        targetChip: "esp32s3",
        targetHardware: "Waveshare ESP32-S3-LCD-3.16",
        flashMode: "dio",
        flashFreq: "80m",
        flashSize: "16MB",
        minimumDesktopVersion: "0.3.0",
        files: [
            .init(offset: "0x10000", path: "vibe_light_esp32.bin", sha256: try app.sha256Hex()),
            .init(offset: "0x0", path: "bootloader.bin", sha256: try bootloader.sha256Hex()),
            .init(offset: "0x8000", path: "partition-table.bin", sha256: try partition.sha256Hex()),
        ]
    )
    try manifest.writeJSON(to: directory.appendingPathComponent("manifest.json"))

    let bundle = try FirmwareBundleValidator().validatedBundle(at: directory)
    let command = FirmwareFlashCommand(bundle: bundle, port: "/dev/cu.usbmodem2101", baud: 460_800)

    #expect(bundle.manifest.version == "0.3.0")
    #expect(command.esptoolArguments == [
        "--chip", "esp32s3",
        "--port", "/dev/cu.usbmodem2101",
        "--baud", "460800",
        "--before", "default_reset",
        "--after", "hard_reset",
        "write_flash",
        "--flash_mode", "dio",
        "--flash_freq", "80m",
        "--flash_size", "16MB",
        "0x0", bootloader.path,
        "0x8000", partition.path,
        "0x10000", app.path,
    ])
}

@Test func firmwareChipProbeCommandBuildsNonDestructiveChipIdArguments() {
    let command = FirmwareChipProbeCommand(targetChip: "esp32s3", port: "/dev/cu.usbmodem2101", baud: 460_800)

    #expect(command.esptoolArguments == [
        "--chip", "esp32s3",
        "--port", "/dev/cu.usbmodem2101",
        "--baud", "460800",
        "chip_id",
    ])
}

@Test func firmwareChipProbeResultParsesChipNameAndMacAddress() throws {
    let output = """
    esptool.py v4.11.0
    Serial port /dev/cu.usbmodem1101
    Connecting...
    Chip is ESP32-S3 (QFN56) (revision v0.2)
    Features: WiFi, BLE, Embedded PSRAM 8MB (AP_3v3)
    MAC: 1c:db:d4:7b:3f:cc
    """

    let result = try FirmwareChipProbeResult.parse(output: output)

    #expect(result.chipName == "ESP32-S3 (QFN56)")
    #expect(result.macAddress == "1c:db:d4:7b:3f:cc")
    #expect(result.matches(targetChip: "esp32s3"))
}

@Test func firmwareChipProbeResultDoesNotMatchLessSpecificChipTarget() {
    let result = FirmwareChipProbeResult(
        chipName: "ESP32-S3 (QFN56)",
        macAddress: nil,
        output: "Chip is ESP32-S3 (QFN56)"
    )

    #expect(!result.matches(targetChip: "esp32"))
}

@Test func firmwareChipProbeResultRejectsOutputWithoutChipIdentity() {
    #expect(throws: FirmwareChipProbeError.self) {
        try FirmwareChipProbeResult.parse(output: "esptool.py v4.11.0\nNo serial data received.")
    }
}

@Test func firmwareBundleValidatorRejectsChecksumMismatch() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("boot".utf8).write(to: directory.appendingPathComponent("bootloader.bin"))
    let manifest = FirmwareBundleManifest(
        version: "0.3.0",
        buildCommit: "abc1234",
        targetChip: "esp32s3",
        targetHardware: "Waveshare ESP32-S3-LCD-3.16",
        flashMode: "dio",
        flashFreq: "80m",
        flashSize: "16MB",
        minimumDesktopVersion: "0.3.0",
        files: [
            .init(offset: "0x0", path: "bootloader.bin", sha256: String(repeating: "0", count: 64)),
        ]
    )
    try manifest.writeJSON(to: directory.appendingPathComponent("manifest.json"))

    #expect(throws: FirmwareBundleError.self) {
        try FirmwareBundleValidator().validatedBundle(at: directory)
    }
}

@Test func serialPortDiscoveryKeepsLikelyEsp32MacOSPortsFirst() {
    let ports = FirmwareSerialPortDiscovery().candidatePorts(from: [
        "/dev/cu.Bluetooth-Incoming-Port",
        "/dev/cu.usbmodem2101",
        "/dev/cu.SLAB_USBtoUART",
        "/dev/cu.wchusbserial1420",
        "/dev/tty.usbmodem2101",
    ])

    #expect(ports == [
        "/dev/cu.usbmodem2101",
        "/dev/cu.wchusbserial1420",
        "/dev/cu.SLAB_USBtoUART",
    ])
}

@Test func firmwareFlasherHelperResourceIsExecutable() throws {
    let resourcesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/VibeLightApp/Resources/FirmwareTools")
    let helperURL = resourcesURL.appendingPathComponent("vibe-light-firmware-flasher")

    #expect(FileManager.default.isExecutableFile(atPath: helperURL.path))
}

@Test func firmwareFlasherHelperPrefersVendoredPythonPackagesOverPathEsptool() throws {
    let directory = temporaryDirectory()
    let toolDirectory = directory.appendingPathComponent("FirmwareTools", isDirectory: true)
    let fakeBinDirectory = directory.appendingPathComponent("bin", isDirectory: true)
    let esptoolPackageDirectory = toolDirectory.appendingPathComponent("python-packages/esptool", isDirectory: true)
    try FileManager.default.createDirectory(at: esptoolPackageDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)

    let sourceHelper = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher")
    let helperURL = toolDirectory.appendingPathComponent("vibe-light-firmware-flasher")
    try FileManager.default.copyItem(at: sourceHelper, to: helperURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

    try """
    print("vendored-esptool")
    """.write(to: esptoolPackageDirectory.appendingPathComponent("__main__.py"), atomically: true, encoding: .utf8)

    let fakeSystemEsptool = fakeBinDirectory.appendingPathComponent("esptool.py")
    try """
    #!/usr/bin/env bash
    echo system-esptool
    """.write(to: fakeSystemEsptool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSystemEsptool.path)

    let result = try runProcess(
        executableURL: helperURL,
        arguments: ["--version"],
        environment: [
            "PATH": "\(fakeBinDirectory.path):/usr/bin:/bin:/usr/sbin:/sbin",
        ]
    )

    #expect(result.exitCode == 0)
    #expect(result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "vendored-esptool")
}

@Test func firmwareFlasherHelperStrictModeRejectsSystemFallback() throws {
    let directory = temporaryDirectory()
    let toolDirectory = directory.appendingPathComponent("FirmwareTools", isDirectory: true)
    let fakeBinDirectory = directory.appendingPathComponent("bin", isDirectory: true)
    try FileManager.default.createDirectory(at: toolDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fakeBinDirectory, withIntermediateDirectories: true)

    let sourceHelper = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/VibeLightApp/Resources/FirmwareTools/vibe-light-firmware-flasher")
    let helperURL = toolDirectory.appendingPathComponent("vibe-light-firmware-flasher")
    try FileManager.default.copyItem(at: sourceHelper, to: helperURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)

    let fakeSystemEsptool = fakeBinDirectory.appendingPathComponent("esptool.py")
    try """
    #!/usr/bin/env bash
    echo system-esptool
    """.write(to: fakeSystemEsptool, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSystemEsptool.path)

    let result = try runProcess(
        executableURL: helperURL,
        arguments: ["--version"],
        environment: [
            "PATH": "\(fakeBinDirectory.path):/usr/bin:/bin:/usr/sbin:/sbin",
            "VIBE_LIGHT_FIRMWARE_FLASHER_STRICT": "1",
        ]
    )

    #expect(result.exitCode == 127)
    #expect(result.output.contains("no bundled Python runtime found"))
    #expect(!result.output.contains("system-esptool"))
}

@Test func firmwareFlashProcessRunnerDrainsLargeOutputWhileProcessRuns() async throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scriptURL = directory.appendingPathComponent("large-output-helper.sh")
    try """
    #!/usr/bin/env bash
    python3 - <<'PY'
    import sys
    sys.stdout.write("x" * 200000)
    sys.stdout.flush()
    PY
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let output = try await FirmwareFlashProcessRunner().run(executableURL: scriptURL, arguments: [])

    #expect(output.count == 200_000)
}

@Test func firmwareFlashProcessRunnerStreamsOutputBeforeProcessExits() async throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scriptURL = directory.appendingPathComponent("streaming-output-helper.sh")
    let continueURL = directory.appendingPathComponent("continue")
    try """
    #!/usr/bin/env bash
    python3 -u - "\(continueURL.path)" <<'PY'
    import pathlib
    import sys
    import time

    continue_path = pathlib.Path(sys.argv[1])
    sys.stdout.write("first line\\n")
    sys.stdout.flush()
    deadline = time.time() + 10
    while not continue_path.exists() and time.time() < deadline:
        time.sleep(0.05)
    sys.stdout.write("second line\\n")
    sys.stdout.flush()
    PY
    """.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let collector = OutputChunkCollector()
    let runTask = Task {
        try await FirmwareFlashProcessRunner().run(executableURL: scriptURL, arguments: []) { chunk in
            collector.append(chunk)
        }
    }

    var partialOutput = ""
    for _ in 0..<40 {
        partialOutput = collector.output
        if partialOutput.contains("first line") {
            break
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(partialOutput.contains("first line"))
    #expect(!partialOutput.contains("second line"))
    _ = FileManager.default.createFile(atPath: continueURL.path, contents: Data())

    let output = try await runTask.value
    #expect(output.contains("first line"))
    #expect(output.contains("second line"))
}

@Test func firmwareFlashFailureAdviceExplainsDownloadModeRecovery() {
    let error = FirmwareFlashProcessError(
        status: 2,
        output: "Failed to connect to ESP32-S3: No serial data received."
    )

    let advice = FirmwareFlashFailureAdvice(error: error)

    #expect(advice.kind == .downloadMode)
    #expect(advice.message.contains("按住 BOOT"))
    #expect(advice.message.contains("单击 RST"))
    #expect(advice.message.contains("松开 BOOT"))
}

@Test func firmwareFlashFailureAdviceClassifiesCommonReleaseBlockers() {
    let busy = FirmwareFlashFailureAdvice(
        error: FirmwareFlashProcessError(status: 1, output: "Resource busy: could not open port")
    )
    let checksum = FirmwareFlashFailureAdvice(
        error: FirmwareFlashProcessError(status: 1, output: "Hash of data verified failed")
    )
    let wrongChip = FirmwareFlashFailureAdvice(
        error: FirmwareFlashProcessError(status: 1, output: "This chip is ESP32 not ESP32-S3")
    )

    #expect(busy.kind == .serialPortBusy)
    #expect(busy.message.contains("关闭占用串口"))
    #expect(checksum.kind == .checksumMismatch)
    #expect(checksum.message.contains("重新生成固件包"))
    #expect(wrongChip.kind == .unsupportedChip)
    #expect(wrongChip.message.contains("ESP32-S3"))
}

private func temporaryDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private struct ProcessResult {
    let exitCode: Int32
    let output: String
}

private final class OutputChunkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    var output: String {
        lock.withLock {
            chunks.joined()
        }
    }

    func append(_ chunk: String) {
        lock.withLock {
            chunks.append(chunk)
        }
    }
}

private func runProcess(
    executableURL: URL,
    arguments: [String],
    environment: [String: String] = [:]
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    process.environment = environment

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    try process.run()
    process.waitUntilExit()

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return ProcessResult(
        exitCode: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? ""
    )
}
