import Foundation

public enum HardwareDemoPacketScenario: String, CaseIterable, Identifiable, Sendable {
    case oneRunning = "one-running"
    case mixedWaiting = "mixed-waiting"
    case errorBusy = "error-busy"
    case fiveTasks = "five-tasks"
    case idle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneRunning: "1 running"
        case .mixedWaiting: "2 running + 1 waiting"
        case .errorBusy: "error + busy"
        case .fiveTasks: "5 tasks"
        case .idle: "clear / idle"
        }
    }

    public func packet(timestamp: Date = Date()) -> StatusPacket {
        func updated(_ secondsAgo: TimeInterval) -> Date {
            timestamp.addingTimeInterval(-secondsAgo)
        }

        switch self {
        case .oneRunning:
            return StatusPacket(
                v: 2,
                source: .codex,
                state: .busy,
                detail: "1 running",
                timestamp: timestamp,
                activeCount: 1,
                waitingCount: 0,
                errorCount: 0,
                tasks: [
                    StatusTask(title: "vibe-light", state: .busy, source: .codex, detail: "render screen", updatedAt: updated(192))
                ]
            )
        case .mixedWaiting:
            return StatusPacket(
                v: 2,
                source: .codex,
                state: .waiting,
                detail: "2 running / 1 waiting",
                timestamp: timestamp,
                activeCount: 3,
                waitingCount: 1,
                errorCount: 0,
                tasks: [
                    StatusTask(title: "approval", state: .waiting, source: .codex, detail: "needs confirm", updatedAt: updated(68)),
                    StatusTask(title: "desktop", state: .busy, source: .codex, detail: "sync BLE", updatedAt: updated(192)),
                    StatusTask(title: "firmware", state: .busy, source: .codex, detail: "draw list", updatedAt: updated(42)),
                ]
            )
        case .errorBusy:
            return StatusPacket(
                v: 2,
                source: .codex,
                state: .error,
                detail: "1 failed / 1 running",
                timestamp: timestamp,
                activeCount: 1,
                waitingCount: 0,
                errorCount: 1,
                tasks: [
                    StatusTask(title: "esp32-build", state: .error, source: .codex, detail: "build failed", updatedAt: updated(120)),
                    StatusTask(title: "desktop", state: .busy, source: .codex, detail: "recovering", updatedAt: updated(36)),
                ]
            )
        case .fiveTasks:
            return StatusPacket(
                v: 2,
                source: .codex,
                state: .busy,
                detail: "5 running",
                timestamp: timestamp,
                activeCount: 5,
                waitingCount: 0,
                errorCount: 0,
                tasks: [
                    StatusTask(title: "vibe-light", state: .busy, source: .codex, updatedAt: updated(12)),
                    StatusTask(title: "slideo", state: .busy, source: .codex, updatedAt: updated(24)),
                    StatusTask(title: "gitwikitree", state: .busy, source: .codex, updatedAt: updated(36)),
                    StatusTask(title: "firmware", state: .busy, source: .codex, updatedAt: updated(48)),
                    StatusTask(title: "docs", state: .busy, source: .codex, updatedAt: updated(60)),
                ]
            )
        case .idle:
            return StatusPacket(
                v: 2,
                source: .manual,
                state: .idle,
                detail: "no active tasks",
                timestamp: timestamp,
                activeCount: 0,
                waitingCount: 0,
                errorCount: 0,
                tasks: []
            )
        }
    }
}
