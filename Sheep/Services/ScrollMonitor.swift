import Foundation

/// A scroll report posted by inject.js every 5 s: `{type:"scroll", px, activeSec, path}`.
struct ScrollSample: Equatable {
    var app: WrappedApp
    var section: AppSection
    var path: String
    var px: Double
    var activeSec: Double
    var at: Date = .now
}

/// Consumes scroll samples from wrappers and decides when to intervene.
/// STUB — thresholds, cooldown, nudge call and outcome logging land in the Intervention step (step 4).
@Observable
final class ScrollMonitor {
    /// Set when an intervention should be shown; WrapperView presents `InterventionOverlay` for it.
    var pendingIntervention: InterventionRequest?

    func ingest(_ sample: ScrollSample, mode: Mode) {}

    /// Called when the user navigates to a new path or leaves the wrapper.
    func didNavigate(app: WrappedApp, section: AppSection) {}
    func didLeaveWrapper(app: WrappedApp) {}
}

struct InterventionRequest: Identifiable, Equatable {
    var id = UUID()
    var app: WrappedApp
    var section: AppSection
    var activeMinutes: Double
    var mode: Mode
}
