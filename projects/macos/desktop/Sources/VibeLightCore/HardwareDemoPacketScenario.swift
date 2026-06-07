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
                    StatusTask(title: "vibe-light", state: .busy, source: .codex, detail: "render screen")
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
                    StatusTask(title: "approval", state: .waiting, source: .codex, detail: "needs confirm"),
                    StatusTask(title: "desktop", state: .busy, source: .codex, detail: "sync BLE"),
                    StatusTask(title: "firmware", state: .busy, source: .codex, detail: "draw list"),
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
                    StatusTask(title: "esp32-build", state: .error, source: .codex, detail: "build failed"),
                    StatusTask(title: "desktop", state: .busy, source: .codex, detail: "recovering"),
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
                    StatusTask(title: "vibe-light", state: .busy, source: .codex),
                    StatusTask(title: "slideo", state: .busy, source: .codex),
                    StatusTask(title: "gitwikitree", state: .busy, source: .codex),
                    StatusTask(title: "firmware", state: .busy, source: .codex),
                    StatusTask(title: "docs", state: .busy, source: .codex),
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
