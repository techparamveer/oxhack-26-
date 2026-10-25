# Sheep — Build prompt (paste into your coding agent)

Copy everything below the line into Claude Code / Cursor / Codex. It assumes `docs/MVP_PLAN.md` and `docs/GEMINI_PROMPTS.md` are in the repo.

---

You are building **Sheep**, a native iOS screen-time app, for the OxHack '26 hackathon (theme: **TIME**). We have ~20 hours. Optimise for a reliable, polished 3-minute live demo over completeness.

**Read first:** `docs/MVP_PLAN.md` (architecture, mode policy, build order, demo script) and `docs/GEMINI_PROMPTS.md` (every Gemini prompt, JSON schema and the event log format). Treat both as the spec. If something here conflicts, this prompt wins.

## Product in one paragraph
Sheep gives your time three modes — **Focus, Rest, Play** — and makes the same apps behave differently in each. Instagram and YouTube live inside Sheep as **web-view wrappers**: in Focus, Reels, Explore and Shorts are blocked while DMs, stories, the following feed, search and profiles stay usable; in Rest everything opens and only overuse is nudged. Focus sessions start with 3 questions, Gemini turns them into a plan + checklist, a Pomodoro runs, and finishing earns XP that grows your sheep's wool. Gemini also writes **doom-scroll interventions** inside the wrappers. Sheep has **long-term memory** (Instinct-style markdown files consolidated by Gemini) so it can say *"Yesterday you did 1 of 3 Pomodoros before Reels got you at 22:40 — lock in today."*

## Hard constraints
- **SwiftUI, iOS 17+, Swift 5.9+, `@Observable`.** No third-party packages unless unavoidable.
- **No paid Apple Developer account.** Do NOT use FamilyControls, ManagedSettings, DeviceActivity, push notifications, App Groups or any entitlement. Must run in the Simulator and on a device with a free Personal Team.
- **Supabase backend, offline-first.** Gemini goes through the Supabase Edge Function `gemini` (`supabase/functions/gemini`), which proxies `https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent` with the key stored as the Supabase secret `GEMINI_API_KEY` (Flash-family allowlist, per-user rate limit). Model name is a constant (current Gemini Flash). The app signs in with Supabase anonymous auth and syncs events, memory files, sessions and daily scores in the background through a persisted retry queue; the device stays the source of truth. Small hand-written URLSession client — no supabase-swift package. `SUPABASE_HOST` / `SUPABASE_ANON_KEY` (plus an optional dev-only direct `GEMINI_API_KEY`) come from `Secrets.xcconfig` → Info.plist → `Bundle.main`; `Secrets.xcconfig` stays out of the repo, `Secrets.example.xcconfig` is committed. With no network or no config, every Gemini call returns its hardcoded fallback within its timeout and the whole demo still works.
- **Every Gemini call** uses `responseMimeType: application/json` + `responseSchema`, decodes into `Codable` structs, has a timeout (3 s; consolidator 15 s), and a **hardcoded fallback** so the UI never hangs or errors.
- Persistence: JSON/markdown files in the app's Documents directory + `UserDefaults`. No Core Data/SwiftData needed.
- Never store DM/post content — only app, section/path, timings and the user's own typed answers.

## Design (non-negotiable)
Follow MVP_PLAN "Design — minimal, Nunito everywhere". Summary:
- **Minimal**: warm off-white background, near-black text, hairlines, lots of whitespace. No gradients, shadows, glass, or card stacks. One primary action per screen. One accent colour per mode (Focus `#3D5AFE`, Rest `#2E7D5B`, Play `#E07A2E`), used only for the timer ring, active-mode dot and primary button. Support dark mode.
- **Font: Nunito only**, from `Sheep/Resources/Fonts/` (already in the repo). Add both TTFs to the target and to Info.plist `UIAppFonts`. The variable font's default instance is ExtraLight (PostScript `Nunito-ExtraLight`), so **never** rely on `Font.custom("Nunito", …)` alone. Build every font through a `Theme` helper that sets the `wght` axis:

```swift
import SwiftUI
import UIKit

enum Theme {
    static func nunito(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false) -> Font {
        let name = italic ? "Nunito-ExtraLightItalic" : "Nunito-ExtraLight"
        let wghtTag = 0x77676874 // 'wght'
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: name,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [wghtTag: weight]
        ])
        return Font(UIFont(descriptor: descriptor, size: size) as CTFont)
    }
    static let display  = nunito(76, weight: 800)
    static let title    = nunito(28, weight: 700)
    static let headline = nunito(20, weight: 700)
    static let body     = nunito(17, weight: 400)
    static let caption  = nunito(13, weight: 600)
}
```
  Verify on screen that 400 vs 700 visibly differ (if not, the axis isn't applied). Use `.monospacedDigit()` on the timer. Scale with Dynamic Type via `UIFontMetrics` if time allows.

## Build in this order, committing after each step builds and runs

1. **Skeleton** — Xcode project `Sheep` (bundle id `com.oxhack.sheep`), folder structure from MVP_PLAN, Nunito registered + `Theme.swift`, `Mode` enum, `AppState` (@Observable, persisted), `HomeView` with sheep placeholder, mode buttons, wrapper icons, dev menu (long-press sheep) with: fast timers toggle, seed yesterday, run consolidator, reset all.
2. **Wrappers** — `WebView` (`UIViewRepresentable` over `WKWebView`), mobile Safari user agent, default persistent data store, `inject.js` loaded as a `WKUserScript` at document start:
   - wraps `history.pushState/replaceState` + `popstate` → posts `{type:"nav", path}`
   - accumulates scroll distance + active seconds → posts `{type:"scroll", px, activeSec, path}` every 5 s
   - exposes `window.__sheepSetCSS(css)` to apply per-mode hiding CSS.
   Native `Policy.isAllowed(app:path:mode:)` (table in MVP_PLAN) blocks via overlay + `history.back()`, and in `decidePolicyFor`. Re-apply CSS on mode change. Section detection: Instagram `/reels/`, `/reel/` → reels, `/direct/` → dms, else feed; YouTube `/shorts/` → shorts, else feed.
3. **Focus flow** — `FocusIntakeView` (3 questions, pre-filled from active workstream) → planner call → `FocusSessionView` (Pomodoro ring, checklist, "open wrapper" buttons) → `CongratsView` (reflection call, XP, "What Sheep learned"). `PomodoroTimer` schedules a local notification at end. Fast mode = 1-minute Pomodoros.
4. **Intervention** — `ScrollMonitor` consumes scroll events; thresholds per mode (Focus 30 s fast / 3 min real; Rest 2 min fast / 30 min real; cooldown 2 min). Shows `InterventionOverlay` with nudge call output, sheep animation, primary/secondary buttons. Log outcome `returned` if the user leaves the feed/wrapper within 60 s, else `ignored`.
5. **Rest & Play** — `RestView`: pick activities (Spotify, Netflix, Sport, Walk, custom) with a time limit → timer → local notification with Rest overuse nudge text when exceeded. Shows work apps (Teams, Outlook, Slack) as "muted". `PlayView`: game timer, muted work apps, XP for play under the limit.
6. **Memory** — implement exactly as in MVP_PLAN "Memory" + GEMINI_PROMPTS §6:
   - `EventLog` appends JSONL for every event type listed.
   - `MemoryStore`: read/write markdown files with YAML headers, alias keyword search, snapshot to `history/<timestamp>/` before overwrite.
   - `MemoryConsolidator`: runs on session end and on first launch of a new day (daily rollover); applies returned files; stores `learned[]`.
   - `MemoryContext.build(for:)`: profile + yesterday's daily + last 3 days condensed + active workstreams + top patterns/what-works + alias hits, capped ~6,000 chars.
   - Inject `{{MEMORY}}` into daily brief, planner, nudge, rest and reflection prompts.
   - **Daily brief** card on Home (prompt §1), cached per day with a refresh button.
   - **Seed yesterday** dev action writes realistic yesterday events + `timeline/daily/<yesterday>.md`, `patterns.md`, `what-works.md`, one active workstream ("Dissertation ch.3", due Friday).
7. **XP & sheep** — rules from MVP_PLAN; `SheepView` with 5 wool stages (SF Symbols/shapes are fine; animate with spring), wool shed animation on ignored nudges.
8. **Shortcuts & deep links** — URL scheme `sheep://open/{instagram|youtube}`, `sheep://mode/{focus|rest|play}`. App Intents `StartModeIntent`, `OpenWrapperIntent`. A Setup screen explaining the two Shortcuts automations (Instagram opened → open Sheep; Sheep Rest → turn on iOS Focus).
9. **Notebook** — list memory files, view/edit/delete, show `history` snapshots count.
10. **Polish** — audit every screen against the Design section (remove anything non-essential, check Nunito weights render, dark mode), light haptics, empty states, minimal monochrome sheep app icon.

## Acceptance checks (run the demo script from MVP_PLAN end-to-end)
- With "Seed yesterday" + fast timers, a fresh install can: show a daily brief referencing yesterday → complete a Focus session with a Gemini plan → see Reels/Explore blocked (DMs still open) in the Instagram wrapper → get a memory-aware nudge after scrolling → finish with congrats + XP + "What Sheep learned" → switch to Rest (Reels come back) → get a Rest overuse notification.
- Turning Wi-Fi off still completes the whole flow using fallbacks.
- No compiler warnings about missing entitlements; app installs with a free Personal Team.
- `Secrets.xcconfig` is not tracked by git.
- Every visible string renders in Nunito (no SF Pro fallback), with distinct weights; screens follow the minimal design rules.

Work step by step. After each step: build, fix errors, briefly state what works and what's next. Ask me only when a decision genuinely isn't covered by the docs.
