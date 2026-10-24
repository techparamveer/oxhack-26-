import SwiftUI

/// Pomodoro length: 15 / 25 / 50 min.
struct PomodoroLengthView: View {
    @State private var settings = SheepSettings.shared

    var body: some View {
        SettingsDetail(title: "Pomodoro length",
                       footer: "Each Focus session plans pomodoros of this length. Fast timers in the dev menu override it.") {
            ForEach(Array(SheepSettings.pomodoroOptions.enumerated()), id: \.element) { index, minutes in
                if index > 0 { RowDivider() }
                CheckRow(title: "\(minutes) min", isOn: settings.pomodoroMinutes == minutes) {
                    settings.pomodoroMinutes = minutes
                }
            }
        }
    }
}

/// Sections hidden in the wrappers while Focus is on.
struct BlockedInFocusView: View {
    @State private var settings = SheepSettings.shared

    var body: some View {
        SettingsDetail(title: "Blocked in Focus", footer: "Hidden inside Sheep's Instagram and YouTube while you focus.") {
            ForEach(Array(SheepSettings.blockableSections.enumerated()), id: \.element) { index, section in
                if index > 0 { RowDivider() }
                CheckRow(title: SheepSettings.sectionTitle(section), isOn: settings.isBlocked(section)) {
                    settings.toggleBlocked(section)
                }
            }
        }
    }
}

/// Work apps shown as muted in Rest & Play (muting itself is done by the user's iOS Focus Shortcut).
struct MutedWorkAppsView: View {
    @State private var settings = SheepSettings.shared

    var body: some View {
        SettingsDetail(title: "Work apps to mute", footer: "Muted by your iOS Focus Shortcut while Rest or Play is on.") {
            ForEach(Array(SheepSettings.workApps.enumerated()), id: \.element) { index, app in
                if index > 0 { RowDivider() }
                CheckRow(title: app, isOn: settings.isMuted(app)) { settings.toggleMuted(app) }
            }
        }
    }
}

/// Shared chrome for the Settings detail pickers: one white group + footer note.
private struct SettingsDetail<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Screen(title: title) {
          ScrollView {
            VStack(alignment: .leading, spacing: Theme.space(1)) {
                Surface(padding: EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)) {
                    VStack(spacing: 0) { content() }
                }
                if let footer {
                    Text(footer)
                        .font(Theme.meta)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.top, Theme.space(2))
          }
          .scrollIndicators(.hidden)
          // Cards use the 16 pt card margin inside Screen's 24 pt.
          .padding(.horizontal, Theme.cardMargin - Theme.margin)
        }
    }
}

private struct CheckRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.rowTitle).foregroundStyle(Theme.text)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.focusAccent)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
