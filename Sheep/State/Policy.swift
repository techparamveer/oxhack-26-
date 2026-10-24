import Foundation

/// Mode policy — single source of truth (MVP_PLAN "Mode policy").
/// STUB — the full table, section detection and hiding CSS land in the Wrappers step (step 2).
enum Policy {
    static func section(app: WrappedApp, path: String) -> AppSection { .feed }
    static func isAllowed(app: WrappedApp, path: String, mode: Mode) -> Bool { true }
    static func hidingCSS(app: WrappedApp, mode: Mode) -> String { "" }
}
