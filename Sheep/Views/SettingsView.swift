import SwiftUI

/// Settings sheet (gear on Home): grouped white cards on fog — Sheep, Modes, Privacy.
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SheepSettings.shared
    @State private var confirmForget = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    SettingsGroup("Sheep", top: 28) {
                        HStack {
                            Text("Voice").font(Theme.rowTitle).foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            VoiceSegmented(selection: $settings.voice)
                        }
                        .padding(.vertical, 16)
                        RowDivider()
                        Toggle(isOn: $settings.askBeforeActing) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ask before acting").font(Theme.rowTitle).foregroundStyle(Theme.text)
                                Text("Sheep suggests, you decide")
                                    .font(Theme.nunito(14, weight: 500))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        .tint(Theme.focusAccent)
                        .padding(.vertical, 16)
                        RowDivider()
                        NavigationLink(value: SettingsRoute.notebook) {
                            SettingsRow(title: "What Sheep remembers", value: "Notebook")
                        }
                    }

                    SettingsGroup("Modes") {
                        NavigationLink(value: SettingsRoute.pomodoro) {
                            SettingsRow(title: "Pomodoro length",
                                        value: SheepSettings.pomodoroRowValue(stored: settings.pomodoroMinutes,
                                                                              fastTimers: state.fastTimers))
                        }
                        RowDivider()
                        NavigationLink(value: SettingsRoute.blocked) {
                            SettingsRow(title: "Blocked in Focus", value: settings.blockedSummary)
                        }
                        RowDivider()
                        NavigationLink(value: SettingsRoute.workApps) {
                            SettingsRow(title: "Work apps to mute", value: settings.mutedSummary)
                        }
                        RowDivider()
                        NavigationLink(value: SettingsRoute.shortcuts) {
                            let done = settings.shortcutsDoneCount
                            SettingsRow(title: "Shortcuts setup",
                                        value: done == 0 ? "Set up" : "\(done) of \(SheepSettings.shortcutsTotal) on",
                                        valueColor: done == SheepSettings.shortcutsTotal ? Theme.scoreUp : Theme.secondary)
                        }
                    }

                    SettingsGroup("Privacy") {
                        SettingsRow(title: "Memory stays on this phone", value: "On",
                                    valueColor: Theme.scoreUp, showsChevron: false)
                        RowDivider()
                        Button { confirmForget = true } label: {
                            SettingsRow(title: "Forget everything", titleColor: Theme.scoreDown, showsChevron: false)
                        }
                    }
                }
                .padding(.bottom, Theme.space(4))
            }
            .scrollIndicators(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { settings.reload() }   // also on pop back (e.g. after marking Shortcuts done)
            .buttonStyle(.plain)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .notebook: NotebookView().notebookOpensFilesInPlace()
                case .pomodoro: PomodoroLengthView()
                case .blocked: BlockedInFocusView()
                case .workApps: MutedWorkAppsView()
                case .shortcuts: SetupView()
                }
            }
            .confirmationDialog("Forget everything?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget everything", role: .destructive, action: forgetEverything)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sheep's memory, today's scores and your XP are deleted from this phone.")
            }
        }
        .tint(Theme.text)
        .presentationBackground(Theme.background)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(Theme.wordmark)
                .tracking(Theme.Tracking.wordmark)
                .foregroundStyle(Theme.text)
            Spacer()
            IconCircleButton(systemName: "xmark", label: "Close") { dismiss() }
                .accessibilityIdentifier("settings.close")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 20)
    }

    private func forgetEverything() {
        RestController.notifier.clear(id: RestController.restNotificationID)   // no banner for a wiped session
        RestController.notifier.clear(id: RestController.playNotificationID)
        MemoryReset.forgetEverything()   // memory files, event log (scores), brief cache
        state.resetAll()                 // XP, mode, sessions
        router.popToRoot()
        dismiss()
    }
}

enum SettingsRoute: Hashable {
    case notebook, pomodoro, blocked, workApps, shortcuts
}

/// Caption + white radius-24 card with rows (16 pt side margin).
struct SettingsGroup<Content: View>: View {
    let title: String
    var top: CGFloat = 24
    @ViewBuilder var content: () -> Content

    init(_ title: String, top: CGFloat = 24, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.top = top
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            SectionLabel(title).padding(.horizontal, 8)
            Surface(padding: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)) {
                VStack(spacing: 0) { content() }
            }
        }
        .padding(.horizontal, Theme.cardMargin)
        .padding(.top, top)
    }
}

/// Title left, value + chevron right.
struct SettingsRow: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = Theme.secondary
    var titleColor: Color = Theme.text
    var showsChevron = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.rowTitle)
                .foregroundStyle(titleColor)
                .lineLimit(1)
            Spacer(minLength: 8)
            if value != nil || showsChevron {
                Text([value, showsChevron ? "›" : nil].compactMap { $0 }.joined(separator: " "))
                    .font(Theme.nunito(17, weight: 600, relativeTo: .body))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 1 pt fog line between rows inside a white settings group.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.background).frame(height: 1).frame(maxWidth: .infinity)
    }
}

/// "Lock in" / "Gentle" segmented capsule. Selected segment = ink fill, white text (inverted in dark).
struct VoiceSegmented: View {
    @Binding var selection: SheepVoice

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SheepVoice.allCases) { voice in
                let active = voice == selection
                Button {
                    withAnimation(Theme.spring) { selection = voice }
                } label: {
                    Text(voice.title)
                        .font(Theme.nunito(14, weight: active ? 800 : 700))
                        .foregroundStyle(active ? Theme.surface : Theme.secondary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(active ? Theme.text : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.background))
        .sensoryFeedback(.selection, trigger: selection)
    }
}
