import SwiftUI

/// Sheep's Notebook: every memory file Sheep keeps, grouped into calm sections.
/// Read / edit / delete for trust + transparency (MVP_PLAN "Memory").
///
/// Works as a tab root (no back button, bottom padding for the floating tab bar) and when pushed
/// (e.g. Settings → "What Sheep remembers"). Needs a NavigationStack ancestor to open files.
///
/// Opening a file: by default pushes `Route.notebookFile(path)` through the `Router`, so the root
/// `NavigationStack(path: router.path)` owns it (and `router.path` is non-empty on file screens).
/// Hosts with their OWN NavigationStack (the Settings sheet) apply `.notebookOpensFilesInPlace()`
/// so files push inside that stack instead.
struct NotebookView: View {
    @Environment(\.isPresented) private var isPushed
    @Environment(\.notebookNavigation) private var navigation
    @Environment(Router.self) private var router: Router?
    @State private var groups: [NotebookGroup] = []
    @State private var eventCount = 0
    @State private var snapshotCount = 0
    @State private var selected: NotebookEntry?

    /// Clearance for the floating tab bar.
    static let tabBarClearance: CGFloat = 100

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Notebook")
                        .font(Theme.wordmark)
                        .tracking(Theme.Tracking.wordmark)
                        .foregroundStyle(Theme.text)
                        .padding(.top, Theme.space(isPushed ? 1 : 2))
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                    footer
                }
                .padding(.bottom, Self.tabBarClearance)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: reload)
        .navigationDestination(item: $selected) { entry in
            NotebookFileView(path: entry.path)
        }
    }

    /// Flat on fog (no white cards): caption + hairline-separated rows, same row type as Settings.
    private func section(_ group: NotebookGroup) -> some View {
        FlatGroup(group.section.title) {
            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Hairline() }
                row(entry)
            }
        }
    }

    private func row(_ entry: NotebookEntry) -> some View {
        Button { open(entry) } label: {
            HStack(spacing: Theme.space(1)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let caption = entry.caption { Caption(caption) }
                }
                Spacer(minLength: Theme.space(1))
                RowChevron()
            }
            .padding(.vertical, 14)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this note")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.space(2)) {
            SheepView(woolStage: 0, size: 120)
                .padding(.top, Theme.space(8))
            Text("Sheep hasn't learned anything yet. Finish a focus session and come back.")
                .font(Theme.body)
                .foregroundStyle(Theme.bodyText)
                .multilineTextAlignment(.center)
            #if DEBUG
            Caption("long-press the sheep → seed yesterday")
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.space(2))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.space(0.5)) {
            Caption("\(eventCount) \(eventCount == 1 ? "event" : "events") logged")
            Caption("\(snapshotCount) history \(snapshotCount == 1 ? "snapshot" : "snapshots")")
            Caption("Only apps, times and your own words. Never messages.")
                .padding(.top, Theme.space(1))
        }
        .padding(.top, Theme.space(5))
    }

    private func open(_ entry: NotebookEntry) {
        if navigation == .router, let router {
            router.push(.notebookFile(entry.path))
        } else {
            selected = entry
        }
    }

    private func reload() {
        groups = NotebookModel.groups(from: MemoryStore.shared.list())
        eventCount = EventLog.shared.readAll().count
        snapshotCount = MemoryStore.shared.historySnapshotCount()
    }
}

/// How `NotebookView` opens a file. `.router` (default): `Router.push(.notebookFile(path))` on the
/// root stack. `.inPlace`: a local `navigationDestination` inside whatever NavigationStack hosts it.
enum NotebookNavigation: Sendable {
    case router, inPlace
}

private struct NotebookNavigationKey: EnvironmentKey {
    static let defaultValue: NotebookNavigation = .router
}

extension EnvironmentValues {
    var notebookNavigation: NotebookNavigation {
        get { self[NotebookNavigationKey.self] }
        set { self[NotebookNavigationKey.self] = newValue }
    }
}

extension View {
    /// Use when NotebookView lives in a NavigationStack other than the root one (e.g. the Settings sheet).
    func notebookOpensFilesInPlace() -> some View {
        environment(\.notebookNavigation, .inPlace)
    }
}
