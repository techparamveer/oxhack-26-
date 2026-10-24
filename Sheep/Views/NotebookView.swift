import SwiftUI

/// Sheep's Notebook: every memory file Sheep keeps, grouped into calm sections.
/// Read / edit / delete for trust + transparency (MVP_PLAN "Memory").
///
/// Works as a tab root (no back button, bottom padding for the floating tab bar) and when pushed
/// (e.g. Settings → "What Sheep remembers"). Needs a NavigationStack ancestor to open files.
struct NotebookView: View {
    @Environment(\.isPresented) private var isPushed
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
                        .padding(.horizontal, Theme.margin - Theme.cardMargin)
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
            // Cards use the 16 pt card margin; text blocks add their own 24 pt.
            .padding(.horizontal, Theme.cardMargin - Theme.margin)
        }
        .toolbar(isPushed ? .automatic : .hidden, for: .navigationBar)
        .onAppear(perform: reload)
        .navigationDestination(item: $selected) { entry in
            NotebookFileView(path: entry.path)
        }
    }

    private func section(_ group: NotebookGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            SectionLabel(group.section.title)
                .padding(.horizontal, 20) // aligns with row text inside the card
            Surface(padding: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)) {
                VStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Hairline() }
                        row(entry)
                    }
                }
            }
        }
        .padding(.top, Theme.space(3))
    }

    private func row(_ entry: NotebookEntry) -> some View {
        Button { selected = entry } label: {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
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
        .padding(.horizontal, Theme.margin - Theme.cardMargin)
        .padding(.bottom, Theme.space(2))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.space(0.5)) {
            Caption("\(eventCount) \(eventCount == 1 ? "event" : "events") logged")
            Caption("\(snapshotCount) history \(snapshotCount == 1 ? "snapshot" : "snapshots")")
            Caption("Only apps, times and your own words. Never messages.")
                .padding(.top, Theme.space(1))
        }
        .padding(.top, Theme.space(4))
        .padding(.horizontal, Theme.margin - Theme.cardMargin)
    }

    private func reload() {
        groups = NotebookModel.groups(from: MemoryStore.shared.list())
        eventCount = EventLog.shared.readAll().count
        snapshotCount = MemoryStore.shared.historySnapshotCount()
    }
}
