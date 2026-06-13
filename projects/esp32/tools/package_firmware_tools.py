#!/usr/bin/env python3
"""Install esptool into the macOS app FirmwareTools resource directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import zipfile
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
    source_dir = args.output_dir / "sources"
    tool_python = args.python or str(Path(sys.executable))
    if args.clean:
        if packages_dir.exists():
            shutil.rmtree(packages_dir)
        if args.python_runtime and runtime_dir.exists() and args.python_runtime.resolve() != runtime_dir.resolve():
            shutil.rmtree(runtime_dir)
        if source_dir.exists():
            shutil.rmtree(source_dir)
    packages_dir.mkdir(parents=True, exist_ok=True)

    if args.python_runtime:
        copy_python_runtime(args.python_runtime, runtime_dir)

    if not args.skip_install:
        env = os.environ.copy()
        env.setdefault("PIP_DISABLE_PIP_VERSION_CHECK", "1")

        install_python = args.python or str(Path(sys.executable))
        tool_python = install_python

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
        prune_python_packages(packages_dir)

    if args.require_python_runtime:
        validate_python_runtime(runtime_dir)

    prune_python_packages(packages_dir)
    packages = read_package_metadata(args.output_dir, packages_dir)
    esptool_package = find_package(packages, "esptool")
    esptool_source = None
    if esptool_package:
        esptool_source = ensure_esptool_source_archive(
            args.output_dir,
            source_dir,
            str(esptool_package["version"]),
            tool_python,
            args.pip_timeout,
            args.pip_retries,
        )

    notice_url = write_third_party_notices(args.output_dir, packages, runtime_dir, esptool_source)
    open_source_url = write_open_source_notices(args.output_dir, esptool_package, esptool_source)
    source_offer_url = write_source_offer(args.output_dir, esptool_package, esptool_source)
    if runtime_dir.exists():
        prune_python_runtime(runtime_dir)
    print(f"wrote firmware tool dependencies to {packages_dir}")
    print(f"wrote firmware tool notices to {notice_url}")
    if open_source_url:
        print(f"wrote open source notices to {open_source_url}")
    if source_offer_url:
        print(f"wrote GPL source offer to {source_offer_url}")
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


def prune_python_runtime(runtime_dir: Path) -> None:
    """Remove development-only files from an embedded runtime.

    Gatekeeper validates every sealed resource in the app bundle. A full
    framework-style Python install contains thousands of files that are not
    needed to run `python -m esptool`, and the large file count can make
    assessment fail before the notarization ticket is considered.
    """

    removable_dirs = [
        "include",
        "share",
        "lib/pkgconfig",
        "lib/python3.11/config-3.11-darwin",
        "lib/python3.11/distutils",
        "lib/python3.11/ensurepip",
        "lib/python3.11/idlelib",
        "lib/python3.11/lib2to3",
        "lib/python3.11/site-packages",
        "lib/python3.11/tkinter",
        "lib/python3.11/turtledemo",
        "lib/python3.11/unittest",
        "lib/python3.11/venv",
    ]
    for relative_url in removable_dirs:
        remove_tree(runtime_dir / relative_url)

    for cache_url in runtime_dir.rglob("__pycache__"):
        remove_tree(cache_url)
    for pattern in ("*.pyc", "*.pyo"):
        for file_url in runtime_dir.rglob(pattern):
            remove_file(file_url)
    for binary_url in runtime_dir.glob("bin/*"):
        if binary_url.name not in {"python3", "python3.11"}:
            remove_file(binary_url)

    zip_python_stdlib(runtime_dir)


def prune_python_packages(packages_dir: Path) -> None:
    for cache_url in packages_dir.rglob("__pycache__"):
        remove_tree(cache_url)
    for pattern in ("*.pyc", "*.pyo", "*.pyd"):
        for file_url in packages_dir.rglob(pattern):
            remove_file(file_url)

    removable_paths = [
        "_cffi_backend.cpython-311-darwin.so",
        "bitarray",
        "bitarray-3.8.1.dist-info",
        "bitstring",
        "bitstring-4.4.0.dist-info",
        "cffi",
        "cffi-2.0.0.dist-info",
        "cryptography",
        "cryptography-49.0.0.dist-info",
        "ecdsa",
        "ecdsa-0.19.2.dist-info",
        "espefuse",
        "espsecure",
        "esp_rfc2217_server",
        "pycparser",
        "pycparser-3.0.dist-info",
        "six-1.17.0.dist-info",
        "six.py",
        "tibs",
        "tibs-0.5.7.dist-info",
    ]
    for package_url in ("argcomplete", "argcomplete-3.6.3.dist-info", *removable_paths):
        remove_tree(packages_dir / package_url)
        remove_file(packages_dir / package_url)


def remove_tree(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)


def remove_file(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def zip_python_stdlib(runtime_dir: Path) -> None:
    stdlib_dir = runtime_dir / "lib" / "python3.11"
    if not stdlib_dir.is_dir():
        return

    archive_url = runtime_dir / "lib" / "python311.zip"

    keep_dirs = {stdlib_dir / "lib-dynload"}
    zip_candidates: list[Path] = []
    for child_url in sorted(stdlib_dir.iterdir()):
        if child_url in keep_dirs:
            continue
        if child_url.is_file() and child_url.suffix == ".py":
            zip_candidates.append(child_url)
            continue
        if child_url.is_dir():
            zip_candidates.extend(
                file_url
                for file_url in sorted(child_url.rglob("*"))
                if file_url.is_file() and file_url.suffix == ".py"
            )

    if not zip_candidates:
        if not archive_url.exists():
            raise SystemExit(f"missing Python stdlib archive after pruning: {archive_url}")
        return

    if archive_url.exists():
        archive_url.unlink()

    with zipfile.ZipFile(archive_url, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file_url in zip_candidates:
            archive.write(file_url, file_url.relative_to(stdlib_dir).as_posix())

    for file_url in zip_candidates:
        remove_file(file_url)

    for child_url in sorted(stdlib_dir.iterdir()):
        if child_url in keep_dirs:
            continue
        if child_url.is_dir() and not any(child_url.rglob("*")):
            remove_tree(child_url)


def read_package_metadata(output_dir: Path, packages_dir: Path) -> list[dict[str, object]]:
    packages = []
    for metadata_url in sorted(packages_dir.glob("*.dist-info/METADATA")):
        metadata = Parser().parsestr(metadata_url.read_text(encoding="utf-8", errors="replace"))
        package_dir = metadata_url.parent
        license_files = [
            license_url.relative_to(output_dir).as_posix()
            for license_url in sorted(package_dir.glob("licenses/*"))
            if license_url.is_file()
        ]
        for license_url in sorted(package_dir.glob("LICENSE*")):
            if license_url.is_file():
                relative = license_url.relative_to(output_dir).as_posix()
                if relative not in license_files:
                    license_files.append(relative)
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
                "license_files": license_files,
            }
        )
    return packages


def find_package(packages: list[dict[str, object]], name: str) -> dict[str, object] | None:
    normalized_name = name.casefold().replace("_", "-")
    for package in packages:
        package_name = str(package["name"]).casefold().replace("_", "-")
        if package_name == normalized_name:
            return package
    return None


def ensure_esptool_source_archive(
    output_dir: Path,
    source_dir: Path,
    version: str,
    python_url: str,
    pip_timeout: str,
    pip_retries: str,
) -> dict[str, str]:
    source_dir.mkdir(parents=True, exist_ok=True)
    target_prefix = f"esptool-{version}"

    for archive_url in esptool_source_archives(source_dir):
        if not archive_url.name.startswith(target_prefix):
            archive_url.unlink()

    archive_url = find_esptool_source_archive(source_dir, version)
    if archive_url is None:
        env = os.environ.copy()
        env.setdefault("PIP_DISABLE_PIP_VERSION_CHECK", "1")
        subprocess.check_call(
            [
                python_url,
                "-m",
                "pip",
                "download",
                "--no-binary",
                ":all:",
                "--no-deps",
                "--timeout",
                pip_timeout,
                "--retries",
                pip_retries,
                "--dest",
                str(source_dir),
                f"esptool=={version}",
            ],
            env=env,
        )
        archive_url = find_esptool_source_archive(source_dir, version)

    if archive_url is None:
        raise SystemExit(f"could not download esptool {version} source archive into {source_dir}")

    return {
        "path": archive_url.relative_to(output_dir).as_posix(),
        "sha256": sha256_file(archive_url),
        "url": f"https://pypi.org/project/esptool/{version}/",
        "upstream": "https://github.com/espressif/esptool",
    }


def esptool_source_archives(source_dir: Path) -> list[Path]:
    archives: list[Path] = []
    for pattern in ("esptool-*.tar.gz", "esptool-*.zip", "esptool-*.tar.bz2", "esptool-*.tar.xz"):
        archives.extend(source_dir.glob(pattern))
    return sorted(archive for archive in archives if archive.is_file())


def find_esptool_source_archive(source_dir: Path, version: str) -> Path | None:
    target_prefix = f"esptool-{version}"
    for archive_url in esptool_source_archives(source_dir):
        if archive_url.name.startswith(target_prefix):
            return archive_url
    return None


def sha256_file(file_url: Path) -> str:
    digest = hashlib.sha256()
    with file_url.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_third_party_notices(
    output_dir: Path,
    packages: list[dict[str, object]],
    runtime_dir: Path,
    esptool_source: dict[str, str] | None,
) -> Path:
    runtime_notice = python_runtime_notice(runtime_dir)

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
                ]
            )
            license_files = package.get("license_files", [])
            if license_files:
                joined_files = ", ".join(f"`{license_file}`" for license_file in license_files)
                lines.append(f"- License files: {joined_files}")
            if str(package["name"]).casefold().replace("_", "-") == "esptool" and esptool_source:
                lines.extend(
                    [
                        f"- Corresponding source: `{esptool_source['path']}`",
                        f"- Source SHA-256: `{esptool_source['sha256']}`",
                        f"- Upstream source: {esptool_source['upstream']}",
                    ]
                )
            lines.append("")
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


def write_open_source_notices(
    output_dir: Path,
    esptool_package: dict[str, object] | None,
    esptool_source: dict[str, str] | None,
) -> Path | None:
    if not esptool_package:
        return None

    notice_url = output_dir / "OPEN_SOURCE_NOTICES.md"
    license_files = esptool_package.get("license_files", [])
    lines = [
        "# Firmware Flasher Open Source Notices",
        "",
        "This file is generated for the firmware flashing tools bundled with Vibe Light.",
        "",
        "## esptool",
        "",
        f"- Version: `{esptool_package['version']}`",
        "- License: GPLv2+",
        "- Usage boundary: Vibe Light starts the firmware flasher as a separate helper process; the helper invokes `python -m esptool` with command-line arguments.",
        "- Modification status: Vibe Light does not modify `esptool` in this bundle.",
        f"- Project: {esptool_package['url']}",
        "- Upstream source: https://github.com/espressif/esptool",
    ]
    if license_files:
        lines.append(f"- GPL license file: `{license_files[0]}`")
    if esptool_source:
        lines.extend(
            [
                f"- Corresponding source archive: `{esptool_source['path']}`",
                f"- Source archive SHA-256: `{esptool_source['sha256']}`",
                f"- PyPI source page: {esptool_source['url']}",
            ]
        )
    lines.extend(
        [
            "",
            "If Vibe Light ever modifies `esptool`, the modified corresponding source must be provided under the same GPL terms.",
            "",
            "See `SOURCE_OFFER.md` for the source availability statement for the bundled GPL program.",
            "",
        ]
    )
    notice_url.write_text("\n".join(lines), encoding="utf-8")
    return notice_url


def write_source_offer(
    output_dir: Path,
    esptool_package: dict[str, object] | None,
    esptool_source: dict[str, str] | None,
) -> Path | None:
    if not esptool_package:
        return None

    offer_url = output_dir / "SOURCE_OFFER.md"
    lines = [
        "# Source Offer for Bundled GPL Software",
        "",
        "Vibe Light bundles `esptool` as a separate command-line program used only by the firmware flashing helper.",
        "",
        "## esptool",
        "",
        f"- Version: `{esptool_package['version']}`",
        "- License: GPLv2+",
        "- Modification status: unmodified upstream package",
        "- Upstream source: https://github.com/espressif/esptool",
    ]
    if esptool_source:
        lines.extend(
            [
                f"- Included corresponding source archive: `{esptool_source['path']}`",
                f"- Source archive SHA-256: `{esptool_source['sha256']}`",
                f"- PyPI source page: {esptool_source['url']}",
            ]
        )
    lines.extend(
        [
            "",
            "The release package includes the corresponding source archive listed above. If the archive is missing or unreadable in a copy of this release, request the same source through the Vibe Light release or support channel where you received the binary distribution.",
            "",
            "This fallback source offer is valid for at least three years after the date of binary distribution.",
            "",
        ]
    )
    offer_url.write_text("\n".join(lines), encoding="utf-8")
    return offer_url


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
