import Foundation

/// What a prompt is for — lets MemoryContext pick keyword hits (app, goal).
enum MemoryPurpose {
    case dailyBrief
    case planner(goal: String)
    case nudge(app: WrappedApp, section: AppSection, goal: String?)
    case rest(activity: String)
    case reflection(goal: String)
}

/// Read path for memory, injected as {{MEMORY}} into every Persona prompt.
/// STUB — implemented in the Memory step (MVP_PLAN "Memory", BUILD_PROMPT step 6).
enum MemoryContext {
    static func build(for purpose: MemoryPurpose) -> String {
        "(no memory yet)"
    }
}
