public struct HardwareReconnectPolicy: Sendable {
    public enum Event: Sendable {
        case manualDisconnect
        case unexpectedDisconnect
        case connectFailure
    }

    public enum Action: Equatable, Sendable {
        case none
        case scanAndAutoConnectFirstDevice
    }

    private let autoConnectEnabled: Bool

    public init(autoConnectEnabled: Bool) {
        self.autoConnectEnabled = autoConnectEnabled
    }

    public func action(after event: Event) -> Action {
        guard autoConnectEnabled else {
            return .none
        }

        switch event {
        case .manualDisconnect:
            return .none
        case .unexpectedDisconnect, .connectFailure:
            return .scanAndAutoConnectFirstDevice
        }
    }
}
