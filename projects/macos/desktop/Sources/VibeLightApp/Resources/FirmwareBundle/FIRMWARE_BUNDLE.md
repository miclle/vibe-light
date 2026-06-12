This directory is populated by the firmware bundle packaging step before release builds.

Run:

```bash
projects/esp32/tools/package_firmware_bundle.py
```

The generated files are intentionally ignored by git because they come from
`projects/esp32/build`.
