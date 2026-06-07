import Foundation

public final class EventStore {
    private let limit: Int

    public private(set) var events: [VibeHookEvent]
    public private(set) var currentState: DisplayState
    public private(set) var latestPacket: StatusPacket?

    public init(
        limit: Int = 50,
        events: [VibeHookEvent] = [],
        currentState: DisplayState = .offline,
        latestPacket: StatusPacket? = nil
    ) {
        self.limit = max(1, limit)
        self.events = Array(events.prefix(max(1, limit)))
        self.currentState = currentState
        self.latestPacket = latestPacket
    }

    public func record(_ event: VibeHookEvent) {
        events.insert(event, at: 0)
        if events.count > limit {
            events.removeLast(events.count - limit)
        }

        currentState = event.displayState
        latestPacket = StatusPacket(event: event)
    }

    public func applyManualState(_ state: DisplayState, detail: String? = nil) {
        let event = VibeHookEvent(
            source: .manual,
            kind: state.defaultManualEventKind,
            detail: detail ?? state.diagnosticDetail
        )
        record(event)
    }
}

private extension DisplayState {
    var defaultManualEventKind: HookEventKind {
        switch self {
        case .idle:
            .sessionEnd
        case .busy:
            .preToolUse
        case .waiting:
            .permissionRequest
        case .success:
            .stop
        case .error:
            .stopFailure
        case .offline:
            .permissionDenied
        }
    }
}
