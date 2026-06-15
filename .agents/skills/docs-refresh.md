# Skill: Refresh Project Documentation

Use this workflow when the user asks to update docs according to the current project state, especially phrasing such as "根据项目情况更新文档", "刷新文档", or mentions of README / AGENTS / TODO / docs / .agents together.

## Steps

1. Inspect `git status --short --branch` and note whether there are existing user changes.
2. Run `make docs-context` to collect the repeatable project facts. The script is read-only; use it as a map, not as a replacement for judgment.
3. Read `README.md`, `README.en.md`, `TODO.md` if present, `docs/architecture.md`, `docs/hardware.md`, `projects/esp32/README.md`, `AGENTS.md`, `.agents/rules/` and this skill when the context output says they are relevant.
4. Read the current source paths that define product truth before changing claims about protocol, hooks, BLE, hardware display or verification:
   - `projects/macos/desktop/Sources/VibeLightCore/StatusModels.swift`
   - `projects/macos/desktop/Sources/VibeLightCore/TaskTracker.swift`
   - `projects/macos/desktop/Sources/VibeLightCore/EventLog.swift`
   - `projects/macos/desktop/Sources/VibeLightHook/main.swift`
   - `projects/esp32/main/vibe_status.*`
   - `projects/esp32/main/vibe_display_model.*`
   - `projects/esp32/main/vibe_display.*`
   - `projects/esp32/main/vibe_display_format.c`
   - `projects/esp32/main/vibe_display_score.*`
   - `projects/esp32/tools/render_maze_preview.py`
   - `script/verify.sh`
5. Update docs by responsibility:
   - `README.md` and `README.en.md` for product and quick-start changes.
   - TODO for current state and next work.
   - Architecture for protocol and cross-layer behavior.
   - Hardware docs for board, pin, driver and real-device bring-up facts.
   - ESP32 README for firmware implementation and flashing/build notes.
   - AGENTS and `.agents/rules/` for durable agent workflow.
6. Run `make docs-check`.
7. Run `make quick` when docs mention firmware display, protocol shape, preview tooling, tests or verification behavior.
8. Report changed docs and clearly separate them from any pre-existing code changes.

## Guardrails

- Do not rewrite the protocol from scratch if only display behavior changed.
- Do not claim a hardware path is verified on-device unless the current turn actually flashed or observed the board.
- Do not let `script/docs_refresh_context.sh` output become documentation verbatim; convert it into stable product, architecture or workflow prose.
- Do not put transient git status or momentary branch state into durable docs.
- Do not commit or push unless the user asks for that explicitly.
