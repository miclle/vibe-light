import Foundation
import VibeLightCore

@MainActor
final class VibeLightAppModel: ObservableObject {
    @Published var selectedTab: AppTab = .general
    @Published private(set) var currentState: DisplayState = .offline
    @Published private(set) var events: [VibeHookEvent] = []
    @Published private(set) var latestPacket: StatusPacket?
    @Published var checklist = SetupChecklist()
    @Published var launchAtLogin = false
    @Published var autoConnectDevice = true
    @Published var selectedManualState: DisplayState = .idle
    @Published var bridgeMessage = "等待 hook 事件..."

    private let eventLog: EventLog

    init(eventLog: EventLog = EventLog()) {
        self.eventLog = eventLog
        refreshEvents()
    }

    func refreshEvents() {
        do {
            let loadedEvents = try eventLog.readRecent(limit: 80)
            events = loadedEvents

            if let event = loadedEvents.first {
                currentState = event.displayState
                latestPacket = StatusPacket(event: event)
                bridgeMessage = "最近事件：\(event.source.displayName) / \(event.kind.rawValue)"
            }
        } catch {
            bridgeMessage = "读取事件失败：\(error.localizedDescription)"
        }
    }

    func recordManualState() {
        let event = VibeHookEvent(
            source: .manual,
            kind: selectedManualState.manualEventKind,
            detail: selectedManualState.diagnosticDetail
        )
        do {
            try eventLog.append(event)
            refreshEvents()
        } catch {
            bridgeMessage = "写入手动状态失败：\(error.localizedDescription)"
        }
    }

    func markSetupStep(_ step: SetupStep, complete: Bool) {
        checklist.mark(step, as: complete ? .complete : .pending)
    }

    func pollEvents() async {
        while !Task.isCancelled {
            refreshEvents()
            try? await Task.sleep(for: .milliseconds(1_500))
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .setup: "安装向导"
        case .events: "事件"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .setup: "wand.and.stars"
        case .events: "waveform.path.ecg"
        }
    }
}

private extension DisplayState {
    var manualEventKind: HookEventKind {
        switch self {
        case .idle: .sessionEnd
        case .busy: .preToolUse
        case .waiting: .permissionRequest
        case .success: .stop
        case .error: .stopFailure
        case .offline: .permissionDenied
        }
    }
}
