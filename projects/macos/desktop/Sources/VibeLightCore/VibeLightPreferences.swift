import Foundation

public struct VibeLightPreferences {
    private enum Keys {
        static let autoConnectDevice = "autoConnectDevice"
        static let selectedManualState = "selectedManualState"
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
}
