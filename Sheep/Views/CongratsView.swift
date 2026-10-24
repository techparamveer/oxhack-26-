import SwiftUI

/// End of a Focus session: honest headline, XP, wool growing, and "What Sheep learned".
/// Appears instantly with the offline card; live reflection + learned lines fade in as they land.
struct CongratsView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    @State private var woolStage: Int?

    var body: some View {
        Screen {
            if let outcome = state.lastOutcome {
                content(outcome)
            } else {
                Color.clear
            }
        }
        .navigationBarBackButtonHidden(true)
        .task {
            guard woolStage == nil else { return }
            let before = Progress(xp: state.progress.xp - (state.lastOutcome?.xpEarned ?? 0)).woolStage
            woolStage = before
            try? await Task.sleep(nanoseconds: 600_000_000)
            withAnimation(Theme.spring) { woolStage = state.progress.woolStage }
        }
    }

    private func content(_ outcome: SessionOutcome) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    SheepView(woolStage: woolStage ?? state.progress.woolStage)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.space(4))
                    Text("+\(outcome.xpEarned) xp")
                        .font(Theme.title)
                        .foregroundStyle(Theme.scoreUp)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.space(2))
                        .contentTransition(.numericText())
                    Caption("level \(state.progress.level)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.space(1))
                        .contentTransition(.numericText())

                    Text(outcome.headline)
                        .font(Theme.title)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.space(5))
                    Text(outcome.summary)
                        .font(Theme.body)
                        .foregroundStyle(Theme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.space(1))

                    if !outcome.learned.isEmpty {
                        learned(outcome.learned)
                            .padding(.top, Theme.space(4))
                            .transition(.opacity)
                    }

                    if !outcome.nextStep.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.space(1)) {
                            SectionLabel("next")
                            Text(outcome.nextStep)
                                .font(Theme.body)
                                .foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Theme.space(4))
                    }
                }
                .animation(Theme.spring, value: outcome)
            }
            PrimaryButton(title: "done", accent: Mode.focus.accent) { router.popToRoot() }
                .accessibilityIdentifier("focus.congrats.done")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.space(2))
        }
    }

    private func learned(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(1)) {
            Hairline().padding(.bottom, Theme.space(2))
            SectionLabel("what sheep learned")
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(Theme.body)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
