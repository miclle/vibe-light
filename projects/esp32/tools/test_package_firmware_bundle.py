from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("package_firmware_bundle.py")


class PackageFirmwareBundleTests(unittest.TestCase):
    def test_manifest_describes_ota_application_from_build_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            build_dir = root / "build"
            output_dir = root / "bundle"
            (build_dir / "bootloader").mkdir(parents=True)
            (build_dir / "partition_table").mkdir()

            (build_dir / "bootloader" / "bootloader.bin").write_bytes(b"BOOT")
            (build_dir / "partition_table" / "partition-table.bin").write_bytes(b"PART")
            (build_dir / "ota_data_initial.bin").write_bytes(b"OTA-DATA")
            (build_dir / "vibe_light_led.bin").write_bytes(b"LED-APP")
            (build_dir / "flasher_args.json").write_text(
                json.dumps(
                    {
                        "app": {
                            "offset": "0x20000",
                            "file": "vibe_light_led.bin",
                            "encrypted": "false",
                        },
                        "extra_esptool_args": {"chip": "esp32s3"},
                        "flash_files": {
                            "0x0": "bootloader/bootloader.bin",
                            "0x8000": "partition_table/partition-table.bin",
                            "0x10000": "ota_data_initial.bin",
                            "0x20000": "vibe_light_led.bin",
                        },
                        "flash_settings": {
                            "flash_mode": "dio",
                            "flash_freq": "80m",
                            "flash_size": "16MB",
                        },
                    }
                ),
                encoding="utf-8",
            )
            (build_dir / "project_description.json").write_text(
                json.dumps(
                    {
                        "project_name": "vibe_light_led",
                        "project_version": "v0.1.3-1-g1234567",
                    }
                ),
                encoding="utf-8",
            )

            subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "--build-dir",
                    str(build_dir),
                    "--output-dir",
                    str(output_dir),
                    "--target-hardware",
                    "ESP32-S3-DevKitC-1 N16R8 三色灯",
                    "--ota-capable",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            manifest = json.loads((output_dir / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(
                manifest["ota"],
                {
                    "appVersion": "v0.1.3-1-g1234567",
                    "application": "vibe_light_led.bin",
                    "projectName": "vibe_light_led",
                    "protocolVersion": 1,
                    "secureSigned": False,
                    "sha256": hashlib.sha256(b"LED-APP").hexdigest(),
                    "size": 7,
                },
            )

            usb_only_output_dir = root / "usb-only-bundle"
            subprocess.run(
                [
                    "python3",
                    str(SCRIPT),
                    "--build-dir",
                    str(build_dir),
                    "--output-dir",
                    str(usb_only_output_dir),
                    "--target-hardware",
                    "Waveshare ESP32-S3-LCD-3.16",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            usb_only_manifest = json.loads(
                (usb_only_output_dir / "manifest.json").read_text(encoding="utf-8")
            )
            self.assertNotIn("ota", usb_only_manifest)

            stale_flasher_args = json.loads(
                (build_dir / "flasher_args.json").read_text(encoding="utf-8")
            )
            del stale_flasher_args["flash_files"]["0x10000"]
            (build_dir / "flasher_args.json").write_text(
                json.dumps(stale_flasher_args),
                encoding="utf-8",
            )
            with self.assertRaises(subprocess.CalledProcessError):
                subprocess.run(
                    [
                        "python3",
                        str(SCRIPT),
                        "--build-dir",
                        str(build_dir),
                        "--output-dir",
                        str(root / "invalid-ota-bundle"),
                        "--ota-capable",
                    ],
                    check=True,
                    capture_output=True,
                    text=True,
                )


if __name__ == "__main__":
    unittest.main()
