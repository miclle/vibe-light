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
