import SwiftUI

/// Rest: pick an activity + time limit → wall-clock timer, wrappers with DMs open, work apps muted.
/// A local notification (GEMINI_PROMPTS §4) fires when the limit is exceeded.
struct RestView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    @State private var activity = "Netflix"
    @State private var custom = ""
    @State private var isCustom = false
    @State private var limit = 45
    @FocusState private var customFocused: Bool

    private var accent: Color { Mode.rest.accent }
    private var chosenActivity: String { isCustom ? custom : activity }

    var body: some View {
        Screen(title: "rest") {
            if let session = state.restSession {
                running(session)
            } else {
                picker
            }
        }
        .animation(Theme.spring, value: state.restSession == nil)
        .onAppear { RestController.restoreOveruseNotifications(state: state) }
        .onDisappear {
            // Backed out without starting: don't leave the app sitting in Rest.
            if state.restSession == nil, !router.path.contains(.rest), state.mode == .rest {
                state.setMode(.idle)
            }
        }
    }

    // MARK: Picker

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LimitModeLabel(mode: .rest)
                    .padding(.top, Theme.space(2))
                SectionLabel("what are you resting with?")
                    .padding(.top, Theme.space(3))
                    .padding(.bottom, Theme.space(1))
                ForEach(RestController.activities, id: \.self) { name in
                    activityRow(name, selected: !isCustom && activity == name) {
                        activity = name; isCustom = false; customFocused = false
                    }
                    Hairline()
                }
                customRow

                SectionLabel("for how long?")
                    .padding(.top, Theme.space(3))
                    .padding(.bottom, Theme.space(2))
                LimitPresetPicker(options: RestController.restLimits, selection: $limit, accent: accent)

                Hairline().padding(.vertical, Theme.space(2))
                RestWrappers()
                    .padding(.bottom, Theme.space(2))
                MutedAppsList(mode: .rest)
            }
            .padding(.bottom, Theme.space(2))
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.selection, trigger: isCustom ? "custom" : activity)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Start rest", accent: accent, icon: "play.fill") {
                customFocused = false
                // User gesture — iOS 27 presents Allow here; `schedule` waits for the grant
                // before `add` so we never poison the source with "not authorized".
                NotificationService.shared.requestAuthorizationSoon()
                RestController.startRest(activity: chosenActivity, limitMinutes: limit, state: state)
            }
            .accessibilityIdentifier("rest.start")
            .disabled(isCustom && custom.trimmingCharacters(in: .whitespaces).isEmpty)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.space(1))
            .padding(.bottom, Theme.space(2))
            .background(Theme.background)
        }
    }

    private func activityRow(_ name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(name.lowercased())
                    .font(selected ? Theme.bodyBold : Theme.body)
                    .foregroundStyle(selected ? Theme.text : Theme.secondary)
                Spacer()
                if selected { Checkmark() }
            }
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("rest.activity.\(name.lowercased())")
    }

    private var customRow: some View {
        HStack {
            TextField("", text: $custom, prompt: Text("something else…").font(Theme.body).foregroundStyle(Theme.tertiary))
                .font(isCustom ? Theme.bodyBold : Theme.body)
                .foregroundStyle(Theme.text)
                .focused($customFocused)
                .submitLabel(.done)
                .onChange(of: customFocused) { _, focused in if focused { isCustom = true } }
            if isCustom { Checkmark() }
        }
        .frame(height: 48)
    }

    // MARK: Running

    private func running(_ session: RestSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LimitModeLabel(mode: .rest)
                .padding(.top, Theme.space(2))
            Text(session.activity.lowercased())
                .font(Theme.title)
                .foregroundStyle(Theme.text)
                .padding(.top, Theme.space(1))

            Spacer(minLength: Theme.space(2))
            LimitTimer(startedAt: session.startedAt, limitMinutes: session.limitMinutes,
                       fast: state.fastTimers, accent: accent)
                .frame(maxWidth: .infinity)
            Spacer(minLength: Theme.space(2))

            RestWrappers()
            Hairline().padding(.vertical, Theme.space(2))
            MutedAppsList(mode: .rest)
            PrimaryButton(title: "End rest", accent: accent, icon: "stop.fill") {
                RestController.endRest(state: state)
                router.popToRoot()
            }
            .accessibilityIdentifier("rest.end")
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.space(2))
        }
    }
}

/// "instagram · youtube" plain buttons + "DMs are open in rest".
private struct RestWrappers: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.space(1)) {
                ForEach(Array(WrappedApp.allCases.enumerated()), id: \.element) { index, app in
                    if index > 0 { Text("·").font(Theme.rowTitle).foregroundStyle(Theme.tertiary) }
                    Button { router.open(app) } label: {
                        Text(app.title.lowercased())
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.text)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rest.wrapper.\(app.rawValue)")
                }
            }
            Caption("DMs are open in rest")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Checkmark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(Theme.body)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.text)
    }
}

// MARK: - Shared with PlayView

/// "● Rest mode" — accent dot + label.
struct LimitModeLabel: View {
    let mode: Mode
    var body: some View {
        HStack(spacing: Theme.space(1)) {
            ModeDot(mode: mode)
            Text("\(mode.title) mode")
                .font(Theme.modeLabel)
                .foregroundStyle(mode == .play ? Theme.text : mode.accent)
        }
    }
}

/// Elapsed / limit ring, refreshed from the wall clock (survives navigation and relaunch).
struct LimitTimer: View {
    let startedAt: Date
    let limitMinutes: Int
    let fast: Bool
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: fast ? 0.2 : 1)) { context in
            let elapsed = LimitClock.elapsedSeconds(startedAt: startedAt, now: context.date,
                                                    limitMinutes: limitMinutes, fast: fast)
            let limitSeconds = Double(limitMinutes * 60)
            let over = Int((elapsed - limitSeconds) / 60)
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, elapsed / max(1, limitSeconds)))
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(LimitClock.format(elapsed))
                        .font(Theme.display.monospacedDigit())
                        .tracking(Theme.Tracking.display)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Caption(over > 0 ? "\(over) min over · that's ok" : "of \(limitMinutes) min")
                }
                .padding(.horizontal, Theme.space(4))
            }
            .frame(width: 272, height: 272)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Limit presets as capsules — active one gets the mode-accent outline (like Home's mode pills).
struct LimitPresetPicker: View {
    let options: [Int]
    @Binding var selection: Int
    var accent: Color

    var body: some View {
        HStack(spacing: Theme.space(1)) {
            ForEach(options, id: \.self) { minutes in
                let active = selection == minutes
                Button { withAnimation(Theme.spring) { selection = minutes } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(minutes)")
                            .font(Theme.pillNumber)
                            .monospacedDigit()
                        Text("min").font(Theme.label)
                    }
                    .foregroundStyle(active ? Theme.text : Theme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(active ? Theme.surface : .clear))
                    .overlay(Capsule().strokeBorder(active ? accent : Theme.outline,
                                                    lineWidth: active ? Theme.activeOutlineWidth : Theme.outlineWidth))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(minutes) minutes")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
