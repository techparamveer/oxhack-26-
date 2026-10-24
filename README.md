# Sheep

Screen-time app with Focus / Rest / Play modes, wrapped Instagram/YouTube, a Gemini coach and on-device memory. OxHack '26 (theme: TIME).

## Run
1. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` and paste a Gemini key (optional — without one every call uses offline fallbacks).
2. Open `Sheep.xcodeproj`, pick your Personal Team under Signing, run on an iPhone or the Simulator.
3. Long-press the sheep for the dev menu (fast timers, seed yesterday, run consolidator, reset).

Spec: `docs/`. Agent conventions: `AGENTS.md`. Regenerate the project with `xcodegen generate` only if `project.yml` changes.
