#!/usr/bin/env python3
"""Install esptool into the macOS app FirmwareTools resource directory."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
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
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    packages_dir = args.output_dir / "python-packages"
    if args.clean and packages_dir.exists():
        shutil.rmtree(packages_dir)
    packages_dir.mkdir(parents=True, exist_ok=True)

    subprocess.check_call(
        [
            args.python,
            "-m",
            "pip",
            "install",
            "--upgrade",
            "--target",
            str(packages_dir),
            f"esptool{args.esptool_version}",
        ]
    )

    print(f"wrote firmware tool dependencies to {packages_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
