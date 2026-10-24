import Foundation

/// Start / tick / finish logic for a Focus session. Views stay thin; tests inject the log, Gemini,
/// memory and consolidator.
@MainActor
final class FocusController {
    static let shared = FocusController()

    var eventLog: EventLog
    var gemini: GeminiClient
    var memory: (MemoryPurpose) -> String
    var consolidate: (MemoryConsolidator.Reason) async -> [String]
    var clock: () -> Date

    init(eventLog: EventLog = .shared,
         gemini: GeminiClient = .shared,
         memory: @escaping (MemoryPurpose) -> String = { MemoryContext.build(for: $0) },
         consolidate: @escaping (MemoryConsolidator.Reason) async -> [String] = { await MemoryConsolidator.shared.run(reason: $0) },
         clock: @escaping () -> Date = { Date() }) {
        self.eventLog = eventLog
        self.gemini = gemini
        self.memory = memory
        self.consolidate = consolidate
        self.clock = clock
    }

    // MARK: Settings

    static let pomodoroMinutesKey = "sheep.pomodoroMinutes"

    /// The one place Pomodoro length is read: 1 min with fast timers, else the Settings value (default 25).
    static func pomodoroMinutes(state: AppState, defaults: UserDefaults = .standard) -> Int {
        if state.fastTimers { return 1 }
        let stored = defaults.integer(forKey: pomodoroMinutesKey)
        return stored > 0 ? stored : 25
    }

    // MARK: Plan + start

    func makePlan(answers: [String], pomodoros: Int, pomodoroMinutes: Int, workstream: String?) async -> PlannerPrompt.Response {
        let minutes = pomodoros * pomodoroMinutes
        let fallback = PlannerPrompt.fallback(answers: answers, pomodoros: pomodoros, minutes: minutes, workstream: workstream)
        let prompt = PlannerPrompt.prompt(minutes: minutes, pomodoros: pomodoros, answers: answers,
                                          memory: memory(.planner(goal: answers.first ?? "")), now: clock())
        var plan = await gemini.generate(PlannerPrompt.Response.self, prompt, fallback: fallback).value
        // Guard against odd live output: keep 3–5 non-empty items.
        plan.checklist = plan.checklist.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if plan.checklist.count < 3 { plan.checklist = fallback.checklist }
        plan.checklist = Array(plan.checklist.prefix(5))
        if plan.title.isEmpty { plan.title = fallback.title }
        if plan.workstream.isEmpty { plan.workstream = fallback.workstream }
        return plan
    }

    @discardableResult
    func start(plan: PlannerPrompt.Response, answers: [String], pomodoros: Int, pomodoroMinutes: Int,
               state: AppState, router: Router) -> FocusSession {
        let session = FocusSession(
            answers: answers,
            title: plan.title,
            opener: plan.opener,
            watchOut: plan.watchOut,
            workstream: plan.workstream,
            checklist: plan.checklist.map { ChecklistItem(text: $0) },
            pomodoros: pomodoros,
            pomodoroMinutes: pomodoroMinutes,
            startedAt: clock()
        )
        state.activeSession = session
        state.setMode(.focus)
        eventLog.append(SheepEvent(type: .sessionStart, mode: .focus, title: session.title, workstream: session.workstream,
                                   plannedMin: session.plannedMinutes, answers: answers))
        PomodoroTimer(session: session).scheduleNotifications(title: session.title)
        router.replaceTop(with: .focusSession)
        return session
    }

    // MARK: Checklist

    func toggle(itemID: UUID, state: AppState) {
        guard var session = state.activeSession,
              let i = session.checklist.firstIndex(where: { $0.id == itemID }) else { return }
        // Un-ticking takes the XP back so ticking can't be farmed.
        if session.checklist[i].done {
            session.checklist[i].done = false
            session.checklist[i].doneAt = nil
            state.progress.add(-XPRules.perChecklistItem)
        } else {
            session.checklist[i].done = true
            session.checklist[i].doneAt = clock()
            state.progress.add(XPRules.perChecklistItem)
            eventLog.append(SheepEvent(type: .checklistDone, item: session.checklist[i].text))
        }
        state.activeSession = session
    }

    // MARK: Finish

    /// Ends the session: logs `session_end` first, shows Congrats immediately with an offline card,
    /// then fills in the live reflection and "What Sheep learned" as they arrive.
    func finish(state: AppState, router: Router) async {
        guard var session = state.activeSession else { return }
        session.endedAt = clock()
        PomodoroTimer(session: session).cancelNotifications()

        let fast = session.pomodoroMinutes == 1
        let completed = !session.checklist.isEmpty && session.doneCount == session.checklist.count
        // Focused time can't exceed the plan (leaving the screen open overnight isn't focus).
        let focused = min(session.actualMinutes, session.plannedMinutes)
        let fallback = ReflectionPrompt.fallback(session: session)
        let baseXP = XPRules.sessionEnd(focusedMinutes: focused, fast: fast, completed: completed,
                                        reflectionBonus: fallback.xpBonus)

        // 1. Log first — the consolidator must see this session.
        eventLog.append(SheepEvent(type: .sessionEnd, mode: .focus, actualMin: Double(session.actualMinutes),
                                   done: session.doneCount, total: session.checklist.count,
                                   xp: baseXP + session.doneCount * XPRules.perChecklistItem))

        // 2. Show Congrats right away.
        state.progress.add(baseXP)
        state.lastOutcome = SessionOutcome(session: session, headline: fallback.headline, summary: fallback.summary,
                                           nextStep: fallback.nextStep, xpEarned: baseXP + session.doneCount * XPRules.perChecklistItem,
                                           learned: [])
        state.activeSession = nil
        state.setMode(.idle)
        router.replaceTop(with: .congrats)

        // 3. Reflection + consolidation in parallel; patch the outcome as each lands.
        let sessionID = session.id
        let prompt = ReflectionPrompt.prompt(session: session, memory: memory(.reflection(goal: session.title)))
        let gemini = self.gemini
        let consolidate = self.consolidate
        async let reflection = gemini.generate(ReflectionPrompt.Response.self, prompt, fallback: fallback)
        async let learned = consolidate(.sessionEnd)

        let r = await reflection
        if r.source == .live, var outcome = state.lastOutcome, outcome.session.id == sessionID {
            let liveXP = XPRules.sessionEnd(focusedMinutes: focused, fast: fast, completed: completed,
                                            reflectionBonus: r.value.xpBonus)
            state.progress.add(liveXP - baseXP)
            outcome.headline = r.value.headline
            outcome.summary = r.value.summary
            outcome.nextStep = r.value.nextStep
            outcome.xpEarned += liveXP - baseXP
            state.lastOutcome = outcome
        }
        let lines = await learned
        if !lines.isEmpty, var outcome = state.lastOutcome, outcome.session.id == sessionID {
            outcome.learned = lines
            state.lastOutcome = outcome
        }
    }
}
