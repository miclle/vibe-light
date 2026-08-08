import Foundation

public enum FirmwareOTAState: String, Codable, Equatable, Sendable {
    case idle
    case ready
    case receiving
    case verifying
    case rebooting
    case complete
    case error
}

public struct FirmwareOTAStatus: Codable, Equatable, Sendable {
    public let v: Int
    public let state: FirmwareOTAState
    public let sessionId: UInt32
    public let committedOffset: Int
    public let imageSize: Int
    public let credits: Int
    public let errorCode: String?
    public let message: String?

    public init(
        v: Int = 1,
        state: FirmwareOTAState,
        sessionId: UInt32,
        committedOffset: Int,
        imageSize: Int,
        credits: Int,
        errorCode: String? = nil,
        message: String? = nil
    ) {
        self.v = v
        self.state = state
        self.sessionId = sessionId
        self.committedOffset = committedOffset
        self.imageSize = imageSize
        self.credits = credits
        self.errorCode = errorCode
        self.message = message
    }
}

public struct FirmwareOTARequest: Equatable, Sendable {
    public let deviceID: String
    public let applicationURL: URL
    public let sessionID: UInt32
    public let imageSize: Int
    public let projectName: String
    public let appVersion: String
    public let sha256: String

    public init(
        deviceID: String,
        applicationURL: URL,
        sessionID: UInt32,
        imageSize: Int,
        projectName: String,
        appVersion: String,
        sha256: String
    ) {
        self.deviceID = deviceID
        self.applicationURL = applicationURL
        self.sessionID = sessionID
        self.imageSize = imageSize
        self.projectName = projectName
        self.appVersion = appVersion
        self.sha256 = sha256
    }
}

public enum FirmwareOTAProgressStage: Equatable, Sendable {
    case preparing
    case transferring
    case verifying
    case rebooting
    case complete
    case failed(String)
    case cancelled
}

public struct FirmwareOTAProgress: Equatable, Sendable {
    public let deviceID: String
    public let targetVersion: String
    public let committedBytes: Int
    public let totalBytes: Int
    public let stage: FirmwareOTAProgressStage

    public init(
        deviceID: String,
        targetVersion: String,
        committedBytes: Int,
        totalBytes: Int,
        stage: FirmwareOTAProgressStage
    ) {
        self.deviceID = deviceID
        self.targetVersion = targetVersion
        self.committedBytes = committedBytes
        self.totalBytes = totalBytes
        self.stage = stage
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(committedBytes) / Double(totalBytes)))
    }
}

public struct FirmwareOTAOffsetTracker: Equatable, Sendable {
    public private(set) var nextOffset = 0
    public private(set) var pendingFrameEnd: Int?
    public private(set) var isSynchronized = false

    public init() {}

    public var canSendNextFrame: Bool {
        isSynchronized && pendingFrameEnd == nil
    }

    public mutating func stageFrame(endingAt endOffset: Int) {
        nextOffset = endOffset
        pendingFrameEnd = endOffset
    }

    public mutating func observeCommittedOffset(_ committedOffset: Int) {
        if !isSynchronized {
            nextOffset = committedOffset
            pendingFrameEnd = nil
            isSynchronized = true
            return
        }
        if let pendingFrameEnd, committedOffset >= pendingFrameEnd {
            self.pendingFrameEnd = nil
        }
    }

    public mutating func prepareForReconnect() {
        pendingFrameEnd = nil
        isSynchronized = false
    }
}

public enum FirmwareOTAStatusPolling {
    public static func shouldPoll(
        state: FirmwareOTAState,
        pendingFrameEnd: Int?,
        finishSent: Bool,
        awaitingReboot: Bool
    ) -> Bool {
        guard !awaitingReboot else { return false }
        switch state {
        case .error, .rebooting, .complete:
            return false
        case .idle, .ready, .receiving, .verifying:
            return pendingFrameEnd != nil || finishSent || state == .verifying
        }
    }
}

public enum FirmwareOTAReconnectPolicy {
    public static func shouldRetryFinish(finishSent: Bool, awaitingReboot: Bool) -> Bool {
        finishSent && !awaitingReboot
    }
}

public enum FirmwareOTAEncodingError: LocalizedError, Equatable {
    case invalidPayloadLength
    case writeValueTooShort

    public var errorDescription: String? {
        switch self {
        case .invalidPayloadLength: "OTA 数据帧不能为空或超过 504 字节。"
        case .writeValueTooShort: "当前 BLE 连接的可写长度不足。"
        }
    }
}

public enum FirmwareOTAEligibility: Equatable, Sendable {
    case ready
    case unsignedBundle
    case unsupportedProtocol
    case usbInitializationRequired
    case signedInitializationRequired
    case wrongProject

    public static func evaluate(
        protocolVersion: Int,
        secureSigned: Bool,
        bundleProjectName: String,
        health: HealthPacket?
    ) -> FirmwareOTAEligibility {
        guard protocolVersion == 1 else { return .unsupportedProtocol }
        guard secureSigned else { return .unsignedBundle }
        guard let health, health.otaCapable == true else { return .usbInitializationRequired }
        guard health.signedUpdatesRequired == true else { return .signedInitializationRequired }
        guard health.projectName == bundleProjectName else { return .wrongProject }
        return .ready
    }
}

public enum FirmwareOTAControl {
    public static func begin(_ request: FirmwareOTARequest) throws -> Data {
        try encode([
            "appVersion": request.appVersion,
            "imageSize": request.imageSize,
            "op": "begin",
            "projectName": request.projectName,
            "sessionId": request.sessionID,
            "sha256": request.sha256,
            "v": 1,
        ])
    }

    public static func finish(sessionID: UInt32) throws -> Data {
        try encode(["op": "finish", "sessionId": sessionID, "v": 1])
    }

    public static func abort(sessionID: UInt32) throws -> Data {
        try encode(["op": "abort", "sessionId": sessionID, "v": 1])
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public enum FirmwareOTAFrame {
    public static let headerSize = 8
    public static let maximumPayloadSize = 504

    public static func encode(
        sessionID: UInt32,
        offset: UInt32,
        payload: Data,
        maximumWriteLength: Int
    ) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximumPayloadSize else {
            throw FirmwareOTAEncodingError.invalidPayloadLength
        }
        guard maximumWriteLength >= headerSize + payload.count else {
            throw FirmwareOTAEncodingError.writeValueTooShort
        }
        var session = sessionID.littleEndian
        var frameOffset = offset.littleEndian
        var frame = Data(bytes: &session, count: MemoryLayout<UInt32>.size)
        frame.append(Data(bytes: &frameOffset, count: MemoryLayout<UInt32>.size))
        frame.append(payload)
        return frame
    }
}
