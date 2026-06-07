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
