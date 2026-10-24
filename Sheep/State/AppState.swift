import Foundation
import Observation

/// App-wide state, persisted to UserDefaults as JSON. Owned by `SheepApp`, passed via `.environment`.
@Observable
final class AppState {
    var mode: Mode = .idle { didSet { save() } }
    var progress = Progress() { didSet { save() } }
    var activeSession: FocusSession? { didSet { save() } }
    var lastOutcome: SessionOutcome? { didSet { save() } }
    var restSession: RestSession? { didSet { save() } }
    var playSession: PlaySession? { didSet { save() } }
    /// Dev toggle: 1-minute Pomodoros and short scroll thresholds for the live demo.
    var fastTimers = true { didSet { save() } }

    @ObservationIgnored let scrollMonitor = ScrollMonitor()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isLoading = false
    static let storageKey = "sheep.appState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        scrollMonitor.attach(self)
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        EventLog.shared.append(SheepEvent(type: .modeChange, mode: newMode))
    }

    func resetAll() {
        isLoading = true
        mode = .idle
        progress = Progress()
        activeSession = nil
        lastOutcome = nil
        restSession = nil
        playSession = nil
        fastTimers = true
        isLoading = false
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var mode: Mode
        var progress: Progress
        var activeSession: FocusSession?
        var lastOutcome: SessionOutcome?
        var restSession: RestSession?
        var playSession: PlaySession?
        var fastTimers: Bool
    }

    private func save() {
        guard !isLoading else { return }
        let snap = Snapshot(mode: mode, progress: progress, activeSession: activeSession, lastOutcome: lastOutcome,
                            restSession: restSession, playSession: playSession, fastTimers: fastTimers)
        if let data = try? JSONEncoder().encode(snap) { defaults.set(data, forKey: Self.storageKey) }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isLoading = true
        progress = snap.progress
        activeSession = snap.activeSession
        lastOutcome = snap.lastOutcome
        restSession = snap.restSession
        playSession = snap.playSession
        fastTimers = snap.fastTimers
        mode = Self.modeForLaunch(snap)
        isLoading = false
        if mode != snap.mode { save() }
    }

    /// A persisted mode only comes back if its matching session is still running. The Rest/Play
    /// pickers set the mode before a session exists; killing the app there must relaunch Idle.
    private static func modeForLaunch(_ snap: Snapshot) -> Mode {
        switch snap.mode {
        case .focus:
            snap.activeSession == nil ? .idle : .focus
        case .rest:
            if let rest = snap.restSession, rest.endedAt == nil { .rest } else { .idle }
        case .play:
            if let play = snap.playSession, play.endedAt == nil { .play } else { .idle }
        case .idle:
            .idle
        }
    }
}
