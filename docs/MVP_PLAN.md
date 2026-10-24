# Sheep — MVP Coding Plan (OxHack '26, theme: TIME)

> **Pitch:** Your time has modes. Sheep makes the same apps behave differently depending on whether it's time to Focus, Rest, or Play — and an AI coach (Gemini) keeps you honest. Time well spent grows your sheep's wool.

## Decisions locked for the MVP

| # | Decision |
|---|---|
| Platform | Native **SwiftUI**, iOS 17+, Xcode. Runs in Simulator and on a personal iPhone with a **free Apple ID** (no paid dev account). |
| Modes | **Focus / Rest / Play** (+ Idle when no session). |
| Blocking | **In-app web-view wrappers only.** No FamilyControls (needs paid account). Native apps are redirected into Sheep via an iOS **Shortcuts automation** ("When Instagram is opened → Open Sheep") using a `sheep://` deep link. |
| Wrappers | **Instagram** (hide Reels + DMs by mode) and **YouTube** (hide Shorts). |
| Gemini | Called directly from the app via REST. Key in a git-ignored `Secrets.xcconfig`. Must ship: **session planner** + **doom-scroll nudge**. Nice: end-of-session reflection. |
| Notifications | Local notifications only (Pomodoro, overuse nudges). "Silence work notifications" = Sheep App Intent + user Shortcut that turns on an iOS Focus. |
| Progress | XP = time well spent. Sheep grows wool per level; doom-scrolling sheds wool. Stored locally. |
| Memory | **On-device, Instinct-style**: markdown memory files + Gemini consolidator after each session and on daily rollover; injected into every prompt so Sheep can say "yesterday you…". User-visible Notebook. Supermemory = production path. |
| FamilyControls, Screen Time usage data, backend, accounts | **Out of scope** → pitch slide "production version". |

## Design — minimal, Nunito everywhere

**Principle:** calm, quiet, lots of space. The screen should feel like time slowing down. If an element doesn't help the user decide what to do with their time, remove it.

**Typeface:** **Nunito** only (variable font, OFL), bundled at `Sheep/Resources/Fonts/`:
- `Nunito-Variable.ttf` (wght 200–1000), `Nunito-Italic-Variable.ttf`, `OFL.txt`.
- ⚠️ The file's default instance is **ExtraLight (200)** and its PostScript name is `Nunito-ExtraLight`. `Font.custom("Nunito", size:)` alone will render ExtraLight. Use a helper that sets the `wght` variation axis explicitly (see `Theme.swift` below).
- Register in Info.plist `UIAppFonts` (`Nunito-Variable.ttf`, `Nunito-Italic-Variable.ttf`).

**Type scale** (one family, contrast via size + weight only):
| Token | Size / weight | Use |
|---|---|---|
| `display` | 64 / 300 | Pomodoro timer digits (monospaced digits) |
| `title` | 28 / 700 | Screen titles, mode names |
| `headline` | 20 / 700 | Nudge headline, card headlines |
| `body` | 17 / 400 | Body text, daily brief, checklist |
| `caption` | 13 / 600 | Labels, meta, small caps-ish UI |

**Colour:** near-monochrome.
- Background `#FAFAF7` (warm off-white), text `#111111`, secondary text `#8A8A85`, hairline `#E8E8E3`.
- Dark mode: background `#0E0E0D`, text `#F2F2EE`, secondary `#7A7A75`, hairline `#222220`.
- **One accent per mode, used sparingly** (timer ring, active mode dot, primary button only): Focus `#3D5AFE`, Rest `#2E7D5B`, Play `#E07A2E`.

**Layout & components:**
- 24 pt side margins, 8 pt spacing grid, generous vertical whitespace.
- No gradients, no drop shadows, no glassmorphism, no card stacks. Separate with whitespace or a 1 px hairline.
- Buttons: full-width pill, filled with mode accent for the one primary action per screen; secondary actions are plain text buttons.
- Icons: SF Symbols, `.light` weight, only where they replace words.
- Sheep: a simple line-drawn/flat sheep, monochrome; wool level shown by size of wool puff, not by badges or bars.
- Motion: subtle springs (≤ 0.4 s), fades. Nudge overlay = blurred page behind + centered text, nothing flashy.
- Copy is short and lowercase-friendly; one idea per screen.

## Demo script (what must work live, ~3 min)
1. Home: sheep with current wool/level + **daily brief from memory**: "Yesterday you did 1 of 3 Pomodoros before Reels got you at 22:40. Lock in today." Tap **Focus**.
2. Intake: 3 questions (What do you want to achieve? What will "done" look like? What usually distracts you?) → **Gemini returns a plan + checklist**.
3. Pomodoro starts (demo: 25 min, with a dev "fast" toggle = 1 min).
4. Open **Instagram wrapper** → Reels tab and DMs are hidden/blocked with a sheep overlay ("Not now — you're focusing on *X*").
5. Scroll the feed for a while → **doom-scroll intervention**: Gemini-written nudge quoting the user's goal, sheep animation.
6. Tick checklist → **Congrats** screen, XP awarded, wool grows.
7. Switch to **Rest** → same Instagram wrapper, DMs now open; pick activity "Netflix" → overuse notification fires (demo threshold).
8. Show **Play** briefly: work apps marked muted, XP for play time.

## Architecture

```
Sheep/
  SheepApp.swift            // app entry, deep-link handling (sheep://open/<app>, sheep://mode/<mode>)
  Design/
    Theme.swift             // Nunito helper (wght axis), type scale, colours, spacing
  Resources/Fonts/          // Nunito-Variable.ttf, Nunito-Italic-Variable.ttf, OFL.txt
  Models/
    Mode.swift              // enum Mode { idle, focus, rest, play } + policy per mode
    WrappedApp.swift        // enum WrappedApp { instagram, youtube } → url, icon, blocked paths per mode
    Session.swift           // goal answers, plan, checklist items, start/end, mode
    Progress.swift          // xp, level, wool; Codable
  State/
    AppState.swift          // @Observable: currentMode, activeSession, progress; persisted to UserDefaults (JSON)
    Policy.swift            // func isAllowed(path:, app:, mode:) -> Bool; hidden CSS selectors per mode
  Services/
    GeminiClient.swift      // generateContent REST, JSON-schema responses
    NotificationService.swift // UNUserNotificationCenter wrappers
    PomodoroTimer.swift     // @Observable timer; schedules local notif at end
    ScrollMonitor.swift     // aggregates scroll events from wrappers, decides when to intervene
  Wrapper/
    WrapperView.swift       // SwiftUI host + overlay
    WebView.swift           // UIViewRepresentable<WKWebView>, message handlers, navigation policy
    inject.js               // path watcher, element hider, scroll reporter
  Views/
    HomeView.swift          // sheep, mode buttons, wrapper icons
    FocusIntakeView.swift   // 3 questions → plan
    FocusSessionView.swift  // pomodoro ring + checklist
    CongratsView.swift
    RestView.swift          // activity picker + timer
    PlayView.swift
    SheepView.swift         // wool level visual / animation
    InterventionOverlay.swift
  Intents/
    SheepIntents.swift      // AppIntents: StartModeIntent(mode), OpenWrapperIntent(app)
  Secrets.xcconfig          // GEMINI_API_KEY (git-ignored) → Info.plist → Bundle lookup
```

### Mode policy (single source of truth — `Policy.swift`)

| | Focus | Rest | Play | Idle |
|---|---|---|---|---|
| Instagram feed | allowed, scroll-monitored (strict) | allowed, monitored (lenient) | allowed | allowed |
| Instagram Reels `/reels/`, `/reel/` | **blocked** | allowed, monitored | allowed | allowed |
| Instagram DMs `/direct/` | **blocked** | allowed | allowed | allowed |
| YouTube Shorts `/shorts/` | **blocked** | allowed, monitored | allowed | allowed |
| Work apps (Teams/Mail — display only) | allowed | muted* | muted* | — |

\* via the user's iOS Focus Shortcut; Sheep shows them as muted in UI.

### Wrapper mechanics (the core trick)
- `WKWebView` with `customUserAgent` = mobile Safari UA (Instagram/YouTube serve proper mobile web).
- Persistent `WKWebsiteDataStore.default()` so logins survive.
- **Blocking by URL, not by fragile CSS**: Instagram/YouTube are SPAs, so `inject.js` wraps `history.pushState/replaceState` + listens to `popstate`, and posts `{type:"nav", path}` to native. Native checks `Policy.isAllowed`; if blocked → show overlay + `history.back()`. Also enforce in `decidePolicyFor navigationAction` for full loads.
- **Hide entry points** with injected CSS from native per mode: e.g. `a[href*="/reels/"], a[href^="/direct/"] { display:none !important }`, `a[href*="/shorts"]`. Re-inject when mode changes (`evaluateJavaScript`).
- **Scroll reporting**: `inject.js` accumulates scroll distance + active seconds, posts `{type:"scroll", px, activeSec, path}` every 5 s.
- `ScrollMonitor`: if continuous active scrolling ≥ threshold (Focus 30 s demo / 3 min real; Rest 2 min demo / 30 min real) → trigger intervention (once per cooldown).

### Gemini (REST, `generateContent`)
- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/<flash-model>:generateContent?key=…` — use the current Flash model from AI Studio.
- Use `generationConfig.responseMimeType = "application/json"` + `responseSchema` so Swift can `Codable`-decode.
- **Planner** — input: 3 answers + session length. Output:
  `{ "title": str, "plan": str (≤2 sentences), "checklist": [str] (3–5 items), "encouragement": str }`
- **Nudge** — input: user goal, mode, minutes scrolled, current path (feed/reels), checklist progress. Output:
  `{ "headline": str (≤8 words), "message": str (≤25 words, references their goal), "action": "back_to_focus" | "take_break" | "keep_going" }`
- **Reflection** (nice-to-have) — input: session summary. Output: `{ "summary": str, "xpBonus": int (0–50) }`.
- Always have a **hardcoded fallback** response if the call fails or times out (3 s) — the demo must never hang on WiFi.

### Memory — "Sheep remembers yesterday" (Instinct-style, on-device)
Goal: Sheep talks like a friend who was there yesterday — *"Yesterday you planned 3 Pomodoros on your dissertation and did 1 before Reels got you at 22:40. Today we lock in."*

Pattern borrowed from Instinct's memory ([teardown](https://supermemory.ai/blog/reverse-engineering-instinct-memory/)): plain markdown files, keyword lookup (no embeddings), a **background consolidator** that rewrites memory, and the main prompts only **read** it.

**Files** (`Documents/memory/`, each with a header `id / type / aliases / updated`):
```
events.jsonl                    raw append-only log: session start/end, goals, checklist done, nudges + outcome, scroll stats, rest activities
timeline/daily/2026-10-24.md    what happened that day: planned vs done, focus minutes, where you slipped, wins
profile.md                      who you are, current life context, tone that works ("blunt, 'lock in' energy"), autonomy level
knowledge/patterns.md           distraction patterns ("Reels ~12 min into Focus", "worst after 22:00")
knowledge/what-works.md         PROCEDURAL memory: which nudges/actions actually got you back (Instinct lacks this)
workstreams/active/<goal>.md    ongoing goals + deadlines ("Dissertation ch.3 — due Fri 30 Oct")
workstreams/completed/
```

**Write path — `MemoryConsolidator`** (one Gemini call, JSON out):
- Runs at **every session end**, and a **daily rollover** on first app open of a new day (finalises yesterday's `timeline/daily`, refreshes `profile.md`). Dev button to force it.
- Input: current memory files + new events since last run. Output: `{ files: [{path, content}], learned: [str] }`.
- Prompt rules (from Instinct): rewrite, don't append; generalise examples into traits; move temporary details into workstreams; replace wrong facts with **dated corrections**; drop incidental detail; close finished workstreams.
- Before overwriting, copy old files to `history/<timestamp>/` (our "git").

**Read path — `MemoryContext.build(for:)`** (≤ ~1.5k tokens injected into every Gemini prompt):
1. `profile.md`
2. **Yesterday** (`timeline/daily/<yesterday>.md`) + last 3 days condensed — this is what powers "yesterday you…"
3. Active workstreams (goals + deadlines)
4. Top lines of `patterns.md` + `what-works.md`
5. Keyword lookup: grep file aliases for the current app/goal (e.g. "instagram", "reels", "dissertation").

**Where memory shows up (demo-visible):**
- **Daily brief** on Home when opening the app: Gemini line referencing yesterday ("Yesterday: 1/3 Pomodoros, Reels at 22:40. Lock in — dissertation's due Friday.").
- **Focus intake** pre-fills from active workstreams and opens with a callback to yesterday.
- **Nudges** cite patterns + yesterday ("This is the exact minute Reels got you yesterday.") and use the tone in `what-works.md`.
- **Congrats** card: "What Sheep learned today" (`learned[]`).
- **Sheep's Notebook** screen: read / edit / delete memory files (trust + transparency).

**Privacy:** only page paths, timings and the user's own typed answers are stored — never DM/post content. All on-device.

**Demo seeding:** a dev "Seed yesterday" button writes a realistic `events.jsonl` + `timeline/daily/<yesterday>.md` so the "yesterday you…" moment works on day one of the hackathon.

### XP / sheep
- Focus: 10 XP / focused minute-block, +20 per checklist item, +50 session complete.
- Resisted intervention ("back to focus"): +15. Ignored / kept doom-scrolling: −10 (wool sheds).
- Rest/Play: small XP for staying under the time limit you set.
- Level = xp / 100. Wool = 5 visual stages. Animate on change.

### Deep links & Shortcuts
- URL scheme `sheep` in Info.plist. `sheep://open/instagram`, `sheep://open/youtube`, `sheep://mode/focus`.
- App Intents: `StartModeIntent`, `OpenWrapperIntent` (appear in Shortcuts app with no entitlement).
- Setup screen in app explaining the 2 automations: "Instagram opened → Open Sheep Instagram", "Sheep Rest started → Turn on Focus 'Rest' (silences Teams/Mail)".

## Build order (priority = demo path first)

**P0 — skeleton (everyone, ~1 h)**
- [ ] Xcode project `Sheep`, SwiftUI, iOS 17, bundle id, free Personal Team signing; `.gitignore` incl. `Secrets.xcconfig`.
- [ ] `Mode`, `AppState`, `HomeView` with mode buttons + sheep placeholder.

**P1 — demo path (parallel tracks)**
- Track A — Wrappers
  - [ ] `WebView` + `WrapperView` loading Instagram & YouTube, login persists.
  - [ ] `inject.js` nav watcher → native policy → block overlay.
  - [ ] Per-mode CSS hiding; re-inject on mode change.
  - [ ] Scroll reporting → `ScrollMonitor`.
- Track B — Modes & sessions
  - [ ] `FocusIntakeView` (3 questions) → `FocusSessionView` (pomodoro ring + checklist) → `CongratsView`.
  - [ ] `PomodoroTimer` + end notification; dev fast-mode toggle.
  - [ ] `RestView` activity picker + timer + overuse notification.
  - [ ] `PlayView` (simple: timer, muted work apps list, XP).
- Track C — Gemini & progress
  - [ ] `GeminiClient` with schema decoding + fallbacks.
  - [ ] Planner wired into intake; nudge wired into `ScrollMonitor` → `InterventionOverlay`.
  - [ ] `Progress` + XP rules + `SheepView` wool stages/animation.
- Track D — Memory (can be same person as C)
  - [ ] `EventLog` (append JSONL from sessions, nudges, scroll, rest).
  - [ ] `MemoryStore` (markdown files w/ headers, alias grep, history snapshots).
  - [ ] `MemoryConsolidator` (session-end + daily rollover Gemini call).
  - [ ] `MemoryContext.build` injected into planner + nudge prompts.
  - [ ] Daily brief on Home ("yesterday you…") + "What Sheep learned" on Congrats.
  - [ ] "Seed yesterday" dev button.
  - [ ] (P2) Sheep's Notebook screen.

**P2 — integration & polish**
- [ ] Deep links + App Intents + Shortcuts setup screen.
- [ ] Reflection call on session end.
- [ ] Visual polish, sheep art, haptics, app icon.

**P3 — submission**
- [ ] Record backup demo video (in case live WiFi/login fails).
- [ ] Devpost write-up, screenshots, pitch slides (incl. "production: FamilyControls, Screen Time API").

## Timeline (Sat 24 Oct → Sun 25 Oct; clocks go back 02:00 = +1 h)

| Time | Goal |
|---|---|
| Sat 16:00–17:00 | P0 skeleton merged; Gemini key working with a curl test |
| 17:00–22:00 | P1 tracks in parallel |
| 22:00–02:00 | Integrate full demo path end-to-end on a real device |
| 02:00–08:00 | P2 + sleep in shifts |
| Sun 08:00 | **Feature freeze** |
| 08:00–11:00 | Bug fixes, backup video, Devpost, rehearse pitch |
| 11:30 | Submit (deadline 12:00 GMT) |

## Risks & mitigations
- **Instagram login in WKWebView blocked / challenges** → log in early on the demo device; fall back to YouTube as the hero wrapper; record backup video.
- **Instagram DOM/paths change** → URL-based blocking is robust; CSS hiding is cosmetic.
- **Gemini latency/WiFi** → 3 s timeout + canned fallback; pre-warm planner before demo.
- **Free provisioning expiry (7 days)** → irrelevant for hackathon; reinstall before judging if needed.
- **API key leakage** → never commit `Secrets.xcconfig`; rotate key after event.
