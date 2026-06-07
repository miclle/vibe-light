import Foundation

public enum SetupStep: String, CaseIterable, Identifiable, Sendable {
    case installApp
    case installHooks
    case connectDevice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .installApp: "安装桌面应用"
        case .installHooks: "安装 Codex / Claude Hooks"
        case .connectDevice: "连接 VibeLight 设备"
        }
    }

    public var detail: String {
        switch self {
        case .installApp: "把 Vibe Light 保持在后台运行，用于接收本地事件。"
        case .installHooks: "让 AI 编程工具把运行状态转发给本机应用。"
        case .connectDevice: "通过 BLE 连接 ESP32-S3，并写入状态包。"
        }
    }
}

public enum SetupStepStatus: String, Codable, Sendable {
    case pending
    case complete
    case failed
}

public struct SetupChecklist: Equatable, Sendable {
    public private(set) var statuses: [SetupStep: SetupStepStatus]

    public init(statuses: [SetupStep: SetupStepStatus] = [:]) {
        self.statuses = statuses
    }

    public var completedCount: Int {
        SetupStep.allCases.filter { statuses[$0] == .complete }.count
    }

    public var isReady: Bool {
        SetupStep.allCases.allSatisfy { statuses[$0] == .complete }
    }

    public func status(for step: SetupStep) -> SetupStepStatus {
        statuses[step] ?? .pending
    }

    public mutating func mark(_ step: SetupStep, as status: SetupStepStatus) {
        statuses[step] = status
    }
}
