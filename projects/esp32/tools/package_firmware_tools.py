#!/usr/bin/env python3
"""Install esptool into the macOS app FirmwareTools resource directory."""

from __future__ import annotations

import argparse
import json
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
    parser.add_argument("--python")
    parser.add_argument("--esptool-version", default=">=4.8,<5")
    parser.add_argument("--pip-timeout", default="60")
    parser.add_argument("--pip-retries", default="3")
    parser.add_argument("--python-runtime", type=Path, help="Copy a standalone Python runtime into FirmwareTools/python")
    parser.add_argument("--require-python-runtime", action="store_true", help="Fail unless FirmwareTools/python/bin/python3 exists")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--skip-install", action="store_true", help="Only refresh notice files from existing packages")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    packages_dir = args.output_dir / "python-packages"
    runtime_dir = args.output_dir / "python"
    if args.clean:
        if packages_dir.exists():
            shutil.rmtree(packages_dir)
        if args.python_runtime and runtime_dir.exists() and args.python_runtime.resolve() != runtime_dir.resolve():
            shutil.rmtree(runtime_dir)
    packages_dir.mkdir(parents=True, exist_ok=True)

    if args.python_runtime:
        copy_python_runtime(args.python_runtime, runtime_dir)

    if not args.skip_install:
        env = os.environ.copy()
        env.setdefault("PIP_DISABLE_PIP_VERSION_CHECK", "1")

        install_python = args.python or str((runtime_dir / "bin" / "python3") if args.python_runtime else Path(sys.executable))

        subprocess.check_call(
            [
                install_python,
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

    if args.require_python_runtime:
        validate_python_runtime(runtime_dir)

    notice_url = write_third_party_notices(args.output_dir, packages_dir, runtime_dir)
    print(f"wrote firmware tool dependencies to {packages_dir}")
    print(f"wrote firmware tool notices to {notice_url}")
    return 0


def copy_python_runtime(source_dir: Path, runtime_dir: Path) -> None:
    source_dir = source_dir.resolve()
    if source_dir == runtime_dir.resolve():
        validate_python_runtime(runtime_dir)
        return

    python_url = source_dir / "bin" / "python3"
    if not python_url.is_file():
        raise SystemExit(f"python runtime is missing bin/python3: {source_dir}")
    if not os.access(python_url, os.X_OK):
        raise SystemExit(f"python runtime bin/python3 is not executable: {python_url}")

    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)
    shutil.copytree(source_dir, runtime_dir, symlinks=True)
    validate_python_runtime(runtime_dir)


def validate_python_runtime(runtime_dir: Path) -> None:
    python_url = runtime_dir / "bin" / "python3"
    if not python_url.is_file():
        raise SystemExit(f"missing bundled Python runtime: {python_url}")
    if not os.access(python_url, os.X_OK):
        raise SystemExit(f"bundled Python runtime is not executable: {python_url}")


def write_third_party_notices(output_dir: Path, packages_dir: Path, runtime_dir: Path) -> Path:
    packages = []
    runtime_notice = python_runtime_notice(runtime_dir)
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

    if runtime_notice:
        lines.extend(runtime_notice)

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


def python_runtime_notice(runtime_dir: Path) -> list[str]:
    package_json_url = runtime_dir / "package.json"
    license_url = runtime_dir / "LICENSE"
    if not package_json_url.exists() and not license_url.exists():
        return []

    metadata = {}
    if package_json_url.exists():
        metadata = json.loads(package_json_url.read_text(encoding="utf-8"))

    name = metadata.get("name", "Python runtime")
    version = metadata.get("version", "unknown")
    license_name = metadata.get("license", "See bundled LICENSE")
    homepage = metadata.get("homepage") or metadata.get("repository") or "See bundled LICENSE"

    lines = [
        f"## {name} {version}",
        "",
        "- Summary: Bundled Python runtime used by the firmware flashing helper",
        f"- License: {license_name}",
        f"- Project: {homepage}",
    ]
    if license_url.exists():
        lines.append(f"- License file: `{license_url.relative_to(runtime_dir.parent)}`")
    lines.append("")
    return lines


if __name__ == "__main__":
    raise SystemExit(main())
