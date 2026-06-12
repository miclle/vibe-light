#!/usr/bin/env python3
"""Install esptool into the macOS app FirmwareTools resource directory."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from email.parser import Parser
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[3]
DEFAULT_OUTPUT_DIR = (
    ROOT_DIR
    / "projects"
    / "macos"
    / "desktop"
    / "Sources"
    / "VibeLightApp"
    / "Resources"
    / "FirmwareTools"
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--python", default=sys.executable)
    parser.add_argument("--esptool-version", default=">=4.8,<5")
    parser.add_argument("--pip-timeout", default="60")
    parser.add_argument("--pip-retries", default="3")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--skip-install", action="store_true", help="Only refresh notice files from existing packages")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    packages_dir = args.output_dir / "python-packages"
    if args.clean and packages_dir.exists():
        shutil.rmtree(packages_dir)
    packages_dir.mkdir(parents=True, exist_ok=True)

    if not args.skip_install:
        env = os.environ.copy()
        env.setdefault("PIP_DISABLE_PIP_VERSION_CHECK", "1")

        subprocess.check_call(
            [
                args.python,
                "-m",
                "pip",
                "install",
                "--upgrade",
                "--prefer-binary",
                "--timeout",
                args.pip_timeout,
                "--retries",
                args.pip_retries,
                "--target",
                str(packages_dir),
                f"esptool{args.esptool_version}",
            ],
            env=env,
        )

    notice_url = write_third_party_notices(args.output_dir, packages_dir)
    print(f"wrote firmware tool dependencies to {packages_dir}")
    print(f"wrote firmware tool notices to {notice_url}")
    return 0


def write_third_party_notices(output_dir: Path, packages_dir: Path) -> Path:
    packages = []
    for metadata_url in sorted(packages_dir.glob("*.dist-info/METADATA")):
        metadata = Parser().parsestr(metadata_url.read_text(encoding="utf-8", errors="replace"))
        packages.append(
            {
                "name": metadata.get("Name", metadata_url.parent.name),
                "version": metadata.get("Version", "unknown"),
                "summary": metadata.get("Summary", ""),
                "license": (
                    metadata.get("License-Expression")
                    or metadata.get("License")
                    or metadata.get("Classifier", "")
                    or "See package metadata"
                ),
                "url": (
                    metadata.get("Project-URL", "")
                    or metadata.get("Home-page", "")
                    or "See package metadata"
                ),
            }
        )

    notice_url = output_dir / "THIRD_PARTY_NOTICES.md"
    lines = [
        "# Firmware Tool Third-Party Notices",
        "",
        "This file is generated from Python package metadata in `FirmwareTools/python-packages/`.",
        "Regenerate it with `projects/esp32/tools/package_firmware_tools.py --clean` before release builds.",
        "",
    ]

    if packages:
        for package in packages:
            lines.extend(
                [
                    f"## {package['name']} {package['version']}",
                    "",
                    f"- Summary: {package['summary'] or 'See package metadata'}",
                    f"- License: {package['license']}",
                    f"- Project: {package['url']}",
                    "",
                ]
            )
    else:
        lines.extend(
            [
                "No Python package metadata was found.",
                "",
                "Run `projects/esp32/tools/package_firmware_tools.py --clean` to vendor esptool and refresh this notice file.",
                "",
            ]
        )

    notice_url.write_text("\n".join(lines), encoding="utf-8")
    return notice_url


if __name__ == "__main__":
    raise SystemExit(main())
