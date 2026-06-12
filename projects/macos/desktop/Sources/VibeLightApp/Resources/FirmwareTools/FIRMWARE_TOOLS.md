Release builds include the executable flashing helper:

```text
vibe-light-firmware-flasher
```

The helper accepts `esptool`-compatible arguments. Release builds should bundle
a standalone Python runtime and vendor `esptool` dependencies into this
directory:

```bash
projects/esp32/tools/package_firmware_tools.py \
  --clean \
  --python-runtime /path/to/python-runtime \
  --require-python-runtime
```

Generated `python/`, `python-packages/` and `THIRD_PARTY_NOTICES.md` contents
are intentionally ignored by git.

Use `VIBE_LIGHT_FIRMWARE_FLASHER_STRICT=1` during release validation to prove
the helper does not fall back to system Python, Homebrew `esptool` or user PATH.
