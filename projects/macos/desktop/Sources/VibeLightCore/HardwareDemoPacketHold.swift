import Foundation

public struct HardwareDemoPacketHold: Sendable {
    public static let defaultDuration: TimeInterval = 15

    private var holdUntil: Date?
    private let duration: TimeInterval

    public init(duration: TimeInterval = Self.defaultDuration) {
        self.duration = duration
    }

    public mutating func start(at date: Date = Date()) {
        holdUntil = date.addingTimeInterval(duration)
    }

    public func allowsLatestPacketForward(at date: Date = Date()) -> Bool {
        guard let holdUntil else {
            return true
        }

        return date >= holdUntil
    }
}
