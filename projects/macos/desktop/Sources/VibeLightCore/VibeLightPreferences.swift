import Foundation

public struct VibeLightPreferences {
    private enum Keys {
        static let autoConnectDevice = "autoConnectDevice"
        static let selectedManualState = "selectedManualState"
        static let codex7dRedThresholdPercent = "codex7dRedThresholdPercent"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var autoConnectDevice: Bool {
        get {
            guard defaults.object(forKey: Keys.autoConnectDevice) != nil else {
                return true
            }
            return defaults.bool(forKey: Keys.autoConnectDevice)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Keys.autoConnectDevice)
        }
    }

    public var selectedManualState: DisplayState {
        get {
            guard let value = defaults.string(forKey: Keys.selectedManualState),
                  let state = DisplayState(rawValue: value) else {
                return .idle
            }
            return state
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Keys.selectedManualState)
        }
    }

    public var codex7dRedThresholdPercent: Int {
        get {
            guard defaults.object(forKey: Keys.codex7dRedThresholdPercent) != nil else {
                return 10
            }
            return min(100, max(0, defaults.integer(forKey: Keys.codex7dRedThresholdPercent)))
        }
        nonmutating set {
            defaults.set(min(100, max(0, newValue)), forKey: Keys.codex7dRedThresholdPercent)
        }
    }
}
