# Skill: Refresh Project Documentation

Use this workflow when the user asks to update docs according to the current project state.

## Steps

1. Inspect `git status --short --branch` and note whether there are existing user changes.
2. Read `README.md`, `TODO.md` if present, `docs/architecture.md`, `docs/hardware.md`, `projects/esp32/README.md`, `AGENTS.md` and `.agents/rules/`.
3. Read the current source paths that define product truth:
   - `projects/macos/desktop/Sources/VibeLightCore/StatusModels.swift`
   - `projects/macos/desktop/Sources/VibeLightCore/TaskTracker.swift`
   - `projects/esp32/main/vibe_status.*`
   - `projects/esp32/main/vibe_display_model.*`
   - `projects/esp32/main/vibe_display.*`
   - `projects/esp32/tools/render_maze_preview.py`
   - `script/verify.sh`
4. Update docs by responsibility:
   - README for product and quick-start changes.
   - TODO for current state and next work.
   - Architecture for protocol and cross-layer behavior.
   - ESP32 README for firmware implementation and flashing/build notes.
   - AGENTS and `.agents/rules/` for durable agent workflow.
5. Run `git diff --check`.
6. Report changed docs and clearly separate them from any pre-existing code changes.

## Guardrails

- Do not rewrite the protocol from scratch if only display behavior changed.
- Do not claim a hardware path is verified on-device unless the current turn actually flashed or observed the board.
- Do not commit or push unless the user asks for that explicitly.
