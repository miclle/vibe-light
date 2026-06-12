import CryptoKit
import Foundation

public struct FirmwareBundleManifest: Codable, Equatable {
    public struct FlashFile: Codable, Equatable {
        public let offset: String
        public let path: String
        public let sha256: String

        public init(offset: String, path: String, sha256: String) {
            self.offset = offset
            self.path = path
            self.sha256 = sha256
        }

        var numericOffset: Int {
            Int(offset.dropFirst(offset.lowercased().hasPrefix("0x") ? 2 : 0), radix: 16) ?? Int.max
        }
    }

    public let version: String
    public let buildCommit: String
    public let targetChip: String
    public let targetHardware: String
    public let flashMode: String
    public let flashFreq: String
    public let flashSize: String
    public let minimumDesktopVersion: String
    public let files: [FlashFile]

    public init(
        version: String,
        buildCommit: String,
        targetChip: String,
        targetHardware: String,
        flashMode: String,
        flashFreq: String,
        flashSize: String,
        minimumDesktopVersion: String,
        files: [FlashFile]
    ) {
        self.version = version
        self.buildCommit = buildCommit
        self.targetChip = targetChip
        self.targetHardware = targetHardware
        self.flashMode = flashMode
        self.flashFreq = flashFreq
        self.flashSize = flashSize
        self.minimumDesktopVersion = minimumDesktopVersion
        self.files = files
    }

    public var flashFiles: [FlashFile] {
        files.sorted { left, right in
            if left.numericOffset == right.numericOffset {
                return left.path < right.path
            }
            return left.numericOffset < right.numericOffset
        }
    }

    public func writeJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }
}

public struct FirmwareBundle: Equatable {
    public let url: URL
    public let manifest: FirmwareBundleManifest

    public init(url: URL, manifest: FirmwareBundleManifest) {
        self.url = url
        self.manifest = manifest
    }

    public func fileURL(for file: FirmwareBundleManifest.FlashFile) -> URL {
        url.appendingPathComponent(file.path)
    }
}

public enum FirmwareBundleError: Error, Equatable, LocalizedError {
    case missingManifest(URL)
    case missingFile(String)
    case checksumMismatch(path: String, expected: String, actual: String)
    case unsupportedChip(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            "找不到固件 manifest：\(url.path)"
        case .missingFile(let path):
            "固件包缺少文件：\(path)"
        case .checksumMismatch(let path, _, _):
            "固件校验失败：\(path)"
        case .unsupportedChip(let chip):
            "不支持的芯片：\(chip)"
        }
    }
}

public struct FirmwareBundleValidator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validatedBundle(at url: URL) throws -> FirmwareBundle {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw FirmwareBundleError.missingManifest(manifestURL)
        }

        let manifest = try JSONDecoder().decode(FirmwareBundleManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.targetChip.lowercased() == "esp32s3" else {
            throw FirmwareBundleError.unsupportedChip(manifest.targetChip)
        }

        for file in manifest.files {
            let fileURL = url.appendingPathComponent(file.path)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                throw FirmwareBundleError.missingFile(file.path)
            }

            let actual = try fileURL.sha256Hex()
            guard actual.lowercased() == file.sha256.lowercased() else {
                throw FirmwareBundleError.checksumMismatch(path: file.path, expected: file.sha256, actual: actual)
            }
        }

        return FirmwareBundle(url: url, manifest: manifest)
    }
}

public struct FirmwareFlashCommand: Equatable {
    public let bundle: FirmwareBundle
    public let port: String
    public let baud: Int

    public init(bundle: FirmwareBundle, port: String, baud: Int = 460_800) {
        self.bundle = bundle
        self.port = port
        self.baud = baud
    }

    public var esptoolArguments: [String] {
        var arguments = [
            "--chip", bundle.manifest.targetChip,
            "--port", port,
            "--baud", "\(baud)",
            "--before", "default_reset",
            "--after", "hard_reset",
            "write_flash",
            "--flash_mode", bundle.manifest.flashMode,
            "--flash_freq", bundle.manifest.flashFreq,
            "--flash_size", bundle.manifest.flashSize,
        ]

        for file in bundle.manifest.flashFiles {
            arguments.append(file.offset)
            arguments.append(bundle.fileURL(for: file).path)
        }

        return arguments
    }
}

public struct FirmwareChipProbeCommand: Equatable {
    public let targetChip: String
    public let port: String
    public let baud: Int

    public init(targetChip: String, port: String, baud: Int = 460_800) {
        self.targetChip = targetChip
        self.port = port
        self.baud = baud
    }

    public var esptoolArguments: [String] {
        [
            "--chip", targetChip,
            "--port", port,
            "--baud", "\(baud)",
            "chip_id",
        ]
    }
}

public enum FirmwareChipProbeError: Error, Equatable, LocalizedError {
    case missingChipIdentity

    public var errorDescription: String? {
        switch self {
        case .missingChipIdentity:
            "未能从芯片读取输出中识别芯片型号。"
        }
    }
}

public struct FirmwareChipProbeResult: Equatable {
    public let chipName: String
    public let macAddress: String?
    public let output: String

    public init(chipName: String, macAddress: String?, output: String) {
        self.chipName = chipName
        self.macAddress = macAddress
        self.output = output
    }

    public static func parse(output: String) throws -> FirmwareChipProbeResult {
        guard let chipName = parseChipName(from: output) else {
            throw FirmwareChipProbeError.missingChipIdentity
        }
        return FirmwareChipProbeResult(
            chipName: chipName,
            macAddress: parseMACAddress(from: output),
            output: output
        )
    }

    public func matches(targetChip: String) -> Bool {
        Self.primaryChipName(chipName) == Self.normalizedChipName(targetChip)
    }

    private static func parseChipName(from output: String) -> String? {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard let range = line.range(of: "Chip is ") else {
                    return nil
                }
                let suffix = String(line[range.upperBound...])
                let withoutRevision = suffix.components(separatedBy: " (revision").first ?? suffix
                return withoutRevision.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }

    private static func parseMACAddress(from output: String) -> String? {
        output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard let range = line.range(of: "MAC:") else {
                    return nil
                }
                return String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { !$0.isEmpty }
    }

    private static func normalizedChipName(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func primaryChipName(_ value: String) -> String {
        let normalized = normalizedChipName(value)
        let knownChips = [
            "esp32s3",
            "esp32s2",
            "esp32c6",
            "esp32c5",
            "esp32c3",
            "esp32h2",
            "esp32p4",
            "esp32",
        ]
        return knownChips.first { normalized.hasPrefix($0) } ?? normalized
    }
}

public struct FirmwareFlashProcessRunner: Sendable {
    public init() {}

    public func run(executableURL: URL, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vibe-firmware-flash-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            defer {
                try? outputHandle.close()
                try? FileManager.default.removeItem(at: outputURL)
            }

            process.standardOutput = outputHandle
            process.standardError = outputHandle

            try process.run()
            process.waitUntilExit()

            try outputHandle.close()
            let outputData = try Data(contentsOf: outputURL)
            let outputString = String(data: outputData, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw FirmwareFlashProcessError(status: process.terminationStatus, output: outputString)
            }
            return outputString
        }.value
    }
}

public struct FirmwareFlashProcessError: Error, LocalizedError {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }

    public var errorDescription: String? {
        "helper 退出码 \(status)"
    }
}

public enum FirmwareFlashFailureKind: Equatable {
    case downloadMode
    case serialPortBusy
    case checksumMismatch
    case unsupportedChip
    case helperRuntimeMissing
    case unknown
}

public struct FirmwareFlashFailureAdvice: Equatable {
    public let kind: FirmwareFlashFailureKind
    public let message: String

    public init(error: Error) {
        if let processError = error as? FirmwareFlashProcessError {
            self = Self(status: processError.status, output: processError.output)
        } else {
            self.kind = .unknown
            self.message = "烧录失败：\(error.localizedDescription)"
        }
    }

    public init(status: Int32, output: String) {
        let normalized = output.lowercased()
        if Self.matchesAny(normalized, [
            "failed to connect",
            "no serial data received",
            "wrong boot mode",
            "download mode",
            "timed out waiting for packet header",
        ]) {
            kind = .downloadMode
            message = "烧录失败：设备未进入下载模式。请按住 BOOT，单击 RST，松开 BOOT 后重试。"
        } else if Self.matchesAny(normalized, [
            "resource busy",
            "device busy",
            "could not open port",
            "permission denied",
            "operation not permitted",
        ]) {
            kind = .serialPortBusy
            message = "烧录失败：串口不可用。请关闭占用串口的 monitor、终端或其他应用后重试。"
        } else if Self.matchesAny(normalized, [
            "hash of data verified failed",
            "checksum",
            "digest",
            "sha256",
        ]) {
            kind = .checksumMismatch
            message = "烧录失败：写入校验未通过。请重新生成固件包，检查 USB 连接后重试。"
        } else if normalized.contains("unsupported chip") ||
            normalized.contains("wrong chip") ||
            (normalized.contains("this chip is esp32") && !normalized.contains("esp32-s3")) ||
            normalized.contains("not esp32-s3") {
            kind = .unsupportedChip
            message = "烧录失败：连接的设备不是 ESP32-S3。请确认硬件是 Waveshare ESP32-S3-LCD-3.16。"
        } else if Self.matchesAny(normalized, [
            "no module named esptool",
            "no bundled esptool runtime found",
            "python-packages/esptool",
        ]) {
            kind = .helperRuntimeMissing
            message = "烧录失败：发布包缺少 esptool runtime。请先运行固件工具打包步骤。"
        } else {
            kind = .unknown
            message = "烧录失败：helper 退出码 \(status)。请查看日志后重试。"
        }
    }

    private static func matchesAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

public struct FirmwareSerialPortDiscovery {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func candidatePorts() -> [String] {
        let deviceURLs = (try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/dev", isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []

        return candidatePorts(from: deviceURLs.map { "/dev/\($0.lastPathComponent)" })
    }

    public func candidatePorts(from paths: [String]) -> [String] {
        paths
            .filter { path in
                let name = URL(fileURLWithPath: path).lastPathComponent
                return name.hasPrefix("cu.usbmodem") ||
                    name.hasPrefix("cu.wchusbserial") ||
                    name.hasPrefix("cu.SLAB_USBtoUART")
            }
            .sorted { left, right in
                rank(left) == rank(right) ? left < right : rank(left) < rank(right)
            }
    }

    private func rank(_ path: String) -> Int {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.hasPrefix("cu.usbmodem") {
            return 0
        }
        if name.hasPrefix("cu.wchusbserial") {
            return 1
        }
        if name.hasPrefix("cu.SLAB_USBtoUART") {
            return 2
        }
        return 99
    }
}

public extension URL {
    func sha256Hex() throws -> String {
        let data = try Data(contentsOf: self)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
