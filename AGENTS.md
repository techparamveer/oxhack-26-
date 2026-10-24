# Sheep — agent guide

Native SwiftUI iOS 17+ app for OxHack '26. **Spec (in priority order):** `docs/BUILD_PROMPT.md` → `docs/MVP_PLAN.md` → `docs/GEMINI_PROMPTS.md`. Read the sections relevant to your step before coding.

## Hard rules
- **No entitlements, ever**: no FamilyControls / ManagedSettings / DeviceActivity / App Groups / push / iCloud / Keychain sharing. Must run on Simulator + free Personal Team. No third-party packages. No backend.
- **Nunito only**: every `Text` uses a `Theme` font (`Theme.title/headline/body/bodyBold/caption/display` or `Theme.nunito(size, weight:)`). Never `.font(.body)`, `.font(.system…)` or `Font.custom("Nunito")`. Timer digits: `Theme.display.monospacedDigit()`.
- **Minimal design** (MVP_PLAN "Design"): `Theme.background/text/secondary/hairline`, mode accent (`mode.accent`) ONLY for timer ring, active mode dot, primary button. No gradients, shadows, glass, cards. One `PrimaryButton` per screen; secondary = `TextButton`. Use `Screen(title:)` for chrome, `Hairline()` to separate, 24 pt margins, 8 pt grid (`Theme.space(n)`), springs ≤0.4 s (`Theme.spring`). Short lowercase-friendly copy. Must look right in dark mode.
- **Gemini**: every call goes through `GeminiClient.shared.generate(T.self, prompt, fallback:)`. Put each prompt in its own file `Sheep/Services/Prompts/<Name>Prompt.swift` with: system text copied verbatim from GEMINI_PROMPTS.md, a user-template builder, the schema as a `JSONValue` literal (lower-case types are fine — the client normalises), temperature, a `Codable` response struct and a **hardcoded fallback** that reads naturally offline. Fill `{{MEMORY}}` with `MemoryContext.build(for:)`. Timeout 3 s (consolidator 15 s). No key → fallback instantly, so the full demo must work offline.
- **Events**: log with `EventLog.shared.append(SheepEvent(type: …))` using the fields in GEMINI_PROMPTS "Event log format". Never store DM/post content — only app, section/path, timings, user's typed answers.
- **Persistence**: `AppState` (UserDefaults JSON) + files under `AppPaths`. No Core Data/SwiftData.

## Project layout
- `project.yml` (XcodeGen) generates `Sheep.xcodeproj`, which is committed. Both targets use **synchronized folders**: any file you add under `Sheep/` or `SheepTests/` is compiled automatically — do NOT edit `project.pbxproj` or `project.yml` unless truly necessary (if you must: edit `project.yml`, run `xcodegen generate`, commit both).
- `Config/Info.plist` (outside the synced folder on purpose). URL scheme `sheep` and `UIAppFonts` are already there.
- Shared contracts from the scaffold: `AppState`, `Router`/`Route`, `Theme`, `Components.swift`, `Mode`, `WrappedApp`/`AppSection`, `FocusSession`/`RestSession`/`PlaySession`/`SessionOutcome`, `Progress`, `EventLog`, `GeminiClient`, `Persona`/`PromptClock`, `NotificationService`, `MemoryContext` (stub), `ScrollMonitor` (stub), `Policy` (stub), `DevActions`.
- Placeholder screens live one-per-file in `Sheep/Views/Placeholders/`. When you implement one, DELETE its placeholder file and create the real one (same type name) so `RootView` routing keeps working.
- Contracts to keep: `XPRules` (all XP amounts), `MemoryStore` (list/read/write/delete/historySnapshotCount), `MemoryConsolidator.shared.run(reason:) async -> [String]` (learned), `MemoryContext.build(for:)`, `ScrollMonitor` (`ingest`, `didNavigate`, `didLeaveWrapper`, `pendingIntervention`), `InterventionOverlay(request:)`, `Policy`.
- Keep edits to shared files (AppState, Router, SheepApp, HomeView, DevMenuView, Components, EventLog, GeminiClient) small and additive — other agents are editing in parallel. Prefer new files/extensions.

## Build & test
Use your OWN simulator so parallel agents don't collide:
```sh
SIM="Sheep-$(basename "$PWD")"
xcrun simctl create "$SIM" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0 2>/dev/null || true
xcodebuild -project Sheep.xcodeproj -scheme Sheep -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath .build/DerivedData test 2>&1 | grep -E "error:|warning: .*Sheep/|failed|Executed|SUCCEEDED|FAILED"
```
Screenshot: `xcrun simctl boot "$SIM"; xcrun simctl install "$SIM" .build/DerivedData/Build/Products/Debug-iphonesimulator/Sheep.app; xcrun simctl launch "$SIM" com.oxhack.sheep; xcrun simctl io "$SIM" screenshot .build/shots/<name>.png`. Delete your simulator when done (`xcrun simctl delete "$SIM"`).

Tests: XCTest in `SheepTests/<Feature>Tests.swift`, `@testable import Sheep`. Test pure logic (policy, thresholds, XP, memory parsing, prompt fill, fallbacks). Use temp dirs (`AppPaths.root = tmp`, `EventLog(fileURL:)`) and `UserDefaults(suiteName:)` — never the real Documents/defaults.

## Git / PRs
- Branch `feat/<step-name>` from latest `origin/main`. Small focused commits. Build + tests green before pushing.
- `gh pr create --base main` with a body: what/why, how to verify in the simulator, test results, screenshots paths if any. End PR body with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`; end commits with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before handing back: `git fetch origin && git rebase origin/main`, rebuild, re-test, force-push with lease.
- `Config/Secrets.xcconfig` is git-ignored — never commit a key.
