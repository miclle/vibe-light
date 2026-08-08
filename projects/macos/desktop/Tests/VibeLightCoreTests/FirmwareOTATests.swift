import Foundation
import Testing
@testable import VibeLightCore

@Suite("FirmwareOTA")
struct FirmwareOTATests {
    @Test func otaManifestExposesApplicationArtifact() throws {
        let data = Data(
            """
            {
              "buildCommit": "1234567",
              "files": [
                {"offset":"0x20000","path":"vibe_light_led.bin","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
              ],
              "flashFreq": "80m",
              "flashMode": "dio",
              "flashSize": "16MB",
              "minimumDesktopVersion": "dev",
              "ota": {
                "appVersion": "v0.1.3-1-g1234567",
                "application": "vibe_light_led.bin",
                "projectName": "vibe_light_led",
                "protocolVersion": 1,
                "secureSigned": true,
                "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "size": 556640
              },
              "targetChip": "esp32s3",
              "targetHardware": "ESP32-S3-DevKitC-1 N16R8 三色灯",
              "version": "dev"
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(FirmwareBundleManifest.self, from: data)
        let bundle = FirmwareBundle(url: URL(fileURLWithPath: "/tmp/vibe-led"), manifest: manifest)

        #expect(manifest.ota?.projectName == "vibe_light_led")
        #expect(manifest.ota?.appVersion == "v0.1.3-1-g1234567")
        #expect(manifest.ota?.secureSigned == true)
        #expect(bundle.otaApplicationURL?.lastPathComponent == "vibe_light_led.bin")
    }

    @Test func legacyManifestRemainsUSBOnly() throws {
        let data = Data(
            """
            {
              "buildCommit": "1234567",
              "files": [],
              "flashFreq": "80m",
              "flashMode": "dio",
              "flashSize": "16MB",
              "minimumDesktopVersion": "dev",
              "targetChip": "esp32s3",
              "targetHardware": "ESP32-S3-DevKitC-1 N16R8 三色灯",
              "version": "dev"
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(FirmwareBundleManifest.self, from: data)
        let bundle = FirmwareBundle(url: URL(fileURLWithPath: "/tmp/vibe-led"), manifest: manifest)

        #expect(manifest.ota == nil)
        #expect(bundle.otaApplicationURL == nil)
    }

    @Test func healthPacketDecodesOTAIdentityAndLegacyPayloads() throws {
        let current = try JSONDecoder().decode(
            HealthPacket.self,
            from: Data(
                """
                {"connected":true,"device":"VibeLight-LED","firmwareVersion":"v0.1.3-1-g1234567","lastState":"idle","otaCapable":true,"projectName":"vibe_light_led","rollbackState":"valid","runningSlot":"ota_0","signedUpdatesRequired":true,"uptimeMs":12000,"v":1}
                """.utf8
            )
        )
        #expect(current.firmwareVersion == "v0.1.3-1-g1234567")
        #expect(current.projectName == "vibe_light_led")
        #expect(current.otaCapable == true)
        #expect(current.runningSlot == "ota_0")
        #expect(current.rollbackState == "valid")
        #expect(current.signedUpdatesRequired == true)

        let legacy = try JSONDecoder().decode(
            HealthPacket.self,
            from: Data(
                """
                {"connected":true,"device":"VibeLight-LED","lastState":"idle","uptimeMs":12000,"v":1}
                """.utf8
            )
        )
        #expect(legacy.firmwareVersion == nil)
        #expect(legacy.projectName == nil)
        #expect(legacy.otaCapable == nil)
        #expect(legacy.runningSlot == nil)
        #expect(legacy.rollbackState == nil)
        #expect(legacy.signedUpdatesRequired == nil)
    }

    @Test func controlAndDataFramesUseStableWireEncoding() throws {
        let request = FirmwareOTARequest(
            deviceID: "device-1",
            applicationURL: URL(fileURLWithPath: "/tmp/vibe_light_led.bin"),
            sessionID: 0x12345678,
            imageSize: 3,
            projectName: "vibe_light_led",
            appVersion: "v0.1.3",
            sha256: String(repeating: "a", count: 64)
        )
        let begin = try #require(String(data: FirmwareOTAControl.begin(request), encoding: .utf8))
        let expectedBegin = "{\"appVersion\":\"v0.1.3\",\"imageSize\":3,\"op\":\"begin\",\"projectName\":\"vibe_light_led\",\"sessionId\":305419896,\"sha256\":\"" + String(repeating: "a", count: 64) + "\",\"v\":1}"
        #expect(begin == expectedBegin)
        #expect(String(data: try FirmwareOTAControl.finish(sessionID: 9), encoding: .utf8) == "{\"op\":\"finish\",\"sessionId\":9,\"v\":1}")

        let frame = try FirmwareOTAFrame.encode(
            sessionID: 0x12345678,
            offset: 0x0a0b0c0d,
            payload: Data([0xaa, 0xbb]),
            maximumWriteLength: 10
        )
        #expect(Array(frame) == [0x78, 0x56, 0x34, 0x12, 0x0d, 0x0c, 0x0b, 0x0a, 0xaa, 0xbb])
    }

    @Test func statusAndProgressDecodeCommittedBytes() throws {
        let status = try JSONDecoder().decode(
            FirmwareOTAStatus.self,
            from: Data("{\"v\":1,\"state\":\"receiving\",\"sessionId\":9,\"committedOffset\":504,\"imageSize\":1008,\"credits\":3}".utf8)
        )
        #expect(status.state == .receiving)
        #expect(status.committedOffset == 504)
        let progress = FirmwareOTAProgress(
            deviceID: "device-1",
            targetVersion: "v0.1.3",
            committedBytes: status.committedOffset,
            totalBytes: status.imageSize,
            stage: .transferring
        )
        #expect(progress.fraction == 0.5)
    }

    @Test func reconnectResynchronizesLostPendingFrameToCommittedOffset() {
        var tracker = FirmwareOTAOffsetTracker()
        tracker.observeCommittedOffset(0)
        tracker.stageFrame(endingAt: 504)

        tracker.prepareForReconnect()
        tracker.observeCommittedOffset(0)

        #expect(tracker.nextOffset == 0)
        #expect(tracker.pendingFrameEnd == nil)
        #expect(tracker.canSendNextFrame)
    }

    @Test func statusPollingContinuesUntilCommitOrTerminalState() {
        #expect(FirmwareOTAStatusPolling.shouldPoll(
            state: .receiving,
            pendingFrameEnd: 504,
            finishSent: false,
            awaitingReboot: false
        ))
        #expect(FirmwareOTAStatusPolling.shouldPoll(
            state: .verifying,
            pendingFrameEnd: nil,
            finishSent: true,
            awaitingReboot: false
        ))
        #expect(!FirmwareOTAStatusPolling.shouldPoll(
            state: .error,
            pendingFrameEnd: 504,
            finishSent: true,
            awaitingReboot: false
        ))
        #expect(!FirmwareOTAStatusPolling.shouldPoll(
            state: .rebooting,
            pendingFrameEnd: nil,
            finishSent: true,
            awaitingReboot: true
        ))
    }

    @Test func disconnectRetriesUnconfirmedFinishOnly() {
        #expect(FirmwareOTAReconnectPolicy.shouldRetryFinish(
            finishSent: true,
            awaitingReboot: false
        ))
        #expect(!FirmwareOTAReconnectPolicy.shouldRetryFinish(
            finishSent: true,
            awaitingReboot: true
        ))
        #expect(!FirmwareOTAReconnectPolicy.shouldRetryFinish(
            finishSent: false,
            awaitingReboot: false
        ))
    }

    @Test func eligibilityRequiresSignedMatchingOTACapableDevice() {
        let ledHealth = HealthPacket(
            device: "VibeLight-LED",
            uptimeMs: 1000,
            connected: true,
            lastState: .idle,
            firmwareVersion: "v0.1.2",
            projectName: "vibe_light_led",
            otaCapable: true,
            runningSlot: "ota_0",
            rollbackState: "valid",
            signedUpdatesRequired: true
        )
        #expect(FirmwareOTAEligibility.evaluate(protocolVersion: 1, secureSigned: true, bundleProjectName: "vibe_light_led", health: ledHealth) == .ready)
        #expect(FirmwareOTAEligibility.evaluate(protocolVersion: 1, secureSigned: false, bundleProjectName: "vibe_light_led", health: ledHealth) == .unsignedBundle)
        #expect(FirmwareOTAEligibility.evaluate(protocolVersion: 2, secureSigned: true, bundleProjectName: "vibe_light_led", health: ledHealth) == .unsupportedProtocol)
        #expect(FirmwareOTAEligibility.evaluate(protocolVersion: 1, secureSigned: true, bundleProjectName: "vibe_light_esp32", health: ledHealth) == .wrongProject)
        #expect(FirmwareOTAEligibility.evaluate(protocolVersion: 1, secureSigned: true, bundleProjectName: "vibe_light_led", health: nil) == .usbInitializationRequired)

        let unsignedInitialization = HealthPacket(
            device: "VibeLight-LED",
            uptimeMs: 1000,
            connected: true,
            lastState: .idle,
            projectName: "vibe_light_led",
            otaCapable: true,
            signedUpdatesRequired: false
        )
        #expect(FirmwareOTAEligibility.evaluate(protocolVersion: 1, secureSigned: true, bundleProjectName: "vibe_light_led", health: unsignedInitialization) == .signedInitializationRequired)
    }
}
