#!/usr/bin/env python3
"""Package the ESP32 build output for the macOS app firmware flasher."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[3]
ESP32_BUILD_DIR = ROOT_DIR / "projects" / "esp32" / "build"
DEFAULT_OUTPUT_DIR = (
    ROOT_DIR
    / "projects"
    / "macos"
    / "desktop"
    / "Sources"
    / "VibeLightApp"
    / "Resources"
    / "FirmwareBundle"
)


def git_commit() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=ROOT_DIR,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return "unknown"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ESP32_BUILD_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--version", default="dev")
    parser.add_argument("--commit", default=git_commit())
    parser.add_argument("--minimum-desktop-version", default="dev")
    args = parser.parse_args()

    flasher_args_url = args.build_dir / "flasher_args.json"
    if not flasher_args_url.exists():
        raise SystemExit(f"missing {flasher_args_url}; run make esp32-build first")

    flasher_args = json.loads(flasher_args_url.read_text(encoding="utf-8"))
    flash_settings = flasher_args.get("flash_settings", {})
    flash_files = flasher_args.get("flash_files", {})
    target_chip = flasher_args.get("extra_esptool_args", {}).get("chip", "esp32s3")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    files = []
    for offset, relative_path in sorted(flash_files.items(), key=lambda item: int(item[0], 16)):
        source = args.build_dir / relative_path
        if not source.exists():
            raise SystemExit(f"missing firmware artifact: {source}")
        destination = args.output_dir / Path(relative_path).name
        shutil.copy2(source, destination)
        files.append(
            {
                "offset": offset,
                "path": destination.name,
                "sha256": sha256(destination),
            }
        )

    manifest = {
        "version": args.version,
        "buildCommit": args.commit,
        "targetChip": target_chip,
        "targetHardware": "Waveshare ESP32-S3-LCD-3.16",
        "flashMode": flash_settings.get("flash_mode", "dio"),
        "flashFreq": flash_settings.get("flash_freq", "80m"),
        "flashSize": flash_settings.get("flash_size", "16MB"),
        "minimumDesktopVersion": args.minimum_desktop_version,
        "files": files,
    }
    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"wrote firmware bundle to {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
