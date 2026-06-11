# Documentation Workflow Rules

## Documentation Surfaces

- `README.md`: product overview, current capabilities and quick start.
- `TODO.md`: current status, near-term priorities and validation focus.
- `docs/architecture.md`: cross-layer architecture, packet contract and design boundaries.
- `docs/hardware.md`: board facts, hardware resources and real-device bring-up notes.
- `projects/esp32/README.md`: firmware-specific build, flash and display behavior.
- `AGENTS.md` and `.agents/`: durable guidance for future agents.

## Rules

- Ground docs in current source and tests. Do not update docs from memory alone.
- For recurring current-state refreshes, start with `make docs-context` to gather the repeatable source/doc facts, then inspect the specific files behind any claims you will edit.
- If code changed packet fields, status rules, animation behavior or hardware assumptions, update docs in the same change.
- Keep README concise and product-facing. Move implementation-heavy details to architecture, firmware or rules docs.
- For docs-only work, avoid staging unrelated code changes. Existing user changes may remain dirty.
- Before reporting completion, run at least `make docs-check`.
- Run `make quick` when the changed docs mention firmware display, protocol shape, preview tooling, tests or verification behavior.

## Automation Boundaries

- `script/docs_refresh_context.sh` is read-only context collection. It should make repeated refreshes faster, not decide the edits.
- `script/docs_check.sh` is a lightweight docs guardrail for whitespace, `CLAUDE.md -> AGENTS.md` compatibility and local `AGENTS.md` references.
- Do not fully automate prose rewrites. The agent must still decide whether a source fact belongs in README, TODO, architecture, hardware, firmware docs or agent guidance.

## Current Project Notes

- The project is already beyond a pure concept doc: ESP32 firmware has a real ST7701 LCD path and host-side tests.
- The current display direction is a top status band, 320px reference maze stage, bottom task panel and firmware-local Codex Pac-Man animation for `busy`.
- Current docs should preserve the hook stdout contract: `vibe-light-hook` writes events only, keeps stdout silent, reports failures on stderr and exits fail-open.
- Current protocol docs should include Codex usage and task timing if relevant: 5h / 7d remaining percentages, optional reset timestamps, task-level `updatedAt` timing, and `CTX` context used percentage as the trailing-label fallback or active-task rotating label.
- Hardware facts should remain tied to Waveshare `ESP32-S3-LCD-3.16` unless the user changes target hardware.
- Hardware verification notes must name the verified time or firmware version when available. Do not imply later commits are on-device verified unless the current turn actually flashed or observed the board.
- Current firmware advertises as `VibeLight-S3`; document BLE examples with that concrete device name unless code changes it.
- Display docs should mention the host-side PNG previews when layout or maze geometry changes.
