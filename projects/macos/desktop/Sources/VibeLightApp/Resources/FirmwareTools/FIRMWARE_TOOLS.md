Release builds include the executable flashing helper:

```text
vibe-light-firmware-flasher
```

The helper accepts `esptool`-compatible arguments. Before a release build, vendor
the Python esptool runtime into this directory:

```bash
projects/esp32/tools/package_firmware_tools.py --clean
```

Generated `python-packages/` contents are intentionally ignored by git.
