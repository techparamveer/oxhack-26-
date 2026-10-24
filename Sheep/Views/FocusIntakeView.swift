import SwiftUI

/// Focus intake: three questions + Pomodoro count, one idea per screen, then the planner call.
struct FocusIntakeView: View {
    @Environment(AppState.self) private var state
    @Environment(Router.self) private var router

    @State private var step = 0
    @State private var answers = ["", "", ""]
    @State private var pomodoros = 3
    @State private var workstream: ActiveWorkstream?
    @State private var didPrefill = false
    @State private var isPlanning = false
    @FocusState private var focusedStep: Int?

    private static let questions = [
        "What do you want to achieve?",
        "What will \u{201C}done\u{201D} look like?",
        "What usually distracts you?"
    ]
    private static let placeholders = [
        "e.g. draft the chapter intro",
        "e.g. 800 words, rough is fine",
        "e.g. instagram reels"
    ]
    private let stepCount = 4

    var body: some View {
        Screen(title: "focus") {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("\(step + 1) of \(stepCount)")
                    .padding(.top, Theme.space(3))
                Group {
                    if step < 3 { question(step) } else { pomodoroPicker }
                }
                .id(step)
                .transition(.opacity)
                Spacer()
                actions
            }
            .padding(.bottom, Theme.space(2))
        }
        .onAppear(perform: prefill)
        .animation(Theme.spring, value: step)
        // No leaving mid-plan: the planner task would otherwise start a session behind the user's back.
        .navigationBarBackButtonHidden(isPlanning)
    }

    // MARK: Steps

    private func question(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.space(2)) {
            Text(Self.questions[i])
                .font(Theme.title)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.space(1))
            TextField("", text: $answers[i],
                      prompt: Text(Self.placeholders[i]).font(Theme.body).foregroundStyle(Theme.secondary),
                      axis: .vertical)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
                .lineLimit(1...4)
                .submitLabel(i < 2 ? .next : .done)
                .focused($focusedStep, equals: i)
                .onChange(of: answers[i]) { _, new in
                    // Vertical fields insert a newline on return — treat it as "next".
                    if new.contains("\n") {
                        answers[i] = new.replacingOccurrences(of: "\n", with: "")
                        advance()
                    }
                }
                .padding(.top, Theme.space(2))
            Hairline()
            if i == 0, let workstream, answers[0] == workstream.goal {
                Caption("from your notebook")
            }
        }
        .onAppear {
            // Next runloop so the freshly inserted field exists before taking focus.
            DispatchQueue.main.async { focusedStep = i }
        }
    }

    private var pomodoroPicker: some View {
        VStack(alignment: .leading, spacing: Theme.space(2)) {
            Text("How many Pomodoros?")
                .font(Theme.title)
                .foregroundStyle(Theme.text)
                .padding(.top, Theme.space(1))
            HStack(spacing: 0) {
                ForEach(1...4, id: \.self) { n in
                    Button {
                        withAnimation(Theme.spring) { pomodoros = n }
                    } label: {
                        VStack(spacing: Theme.space(1)) {
                            Text("\(n)")
                                .font(Theme.nunito(40, weight: n == pomodoros ? 900 : 500))
                                .foregroundStyle(n == pomodoros ? Theme.text : Theme.secondary)
                            Rectangle()
                                .fill(n == pomodoros ? Theme.text : .clear)
                                .frame(width: 24, height: 3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) Pomodoro\(n == 1 ? "" : "s")")
                    .accessibilityAddTraits(n == pomodoros ? .isSelected : [])
                }
            }
            .padding(.top, Theme.space(2))
            Caption(durationNote)
                .frame(maxWidth: .infinity)
        }
        .onAppear { focusedStep = nil }
    }

    private var durationNote: String {
        let minutes = pomodoros * pomodoroMinutes
        return state.fastTimers
            ? "\(minutes) min · fast timers on"
            : "\(minutes) min, back to back"
    }

    private var pomodoroMinutes: Int { FocusController.pomodoroMinutes(state: state) }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: Theme.space(1)) {
            PrimaryButton(title: step < 3 ? "next" : "make a plan", accent: Mode.focus.accent,
                          icon: step < 3 ? nil : "sparkles", isLoading: isPlanning) {
                advance()
            }
            .accessibilityIdentifier("focus.intake.primary")
            .disabled(step == 0 && answers[0].trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(step == 0 && answers[0].trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            TextButton(title: "back") { withAnimation(Theme.spring) { step -= 1 } }
                .opacity(step > 0 && !isPlanning ? 1 : 0)
                .disabled(step == 0 || isPlanning)
        }
        .frame(maxWidth: .infinity)
    }

    private func advance() {
        guard !isPlanning else { return }
        if step == 0 && answers[0].trimmingCharacters(in: .whitespaces).isEmpty { return }
        if step < 3 {
            withAnimation(Theme.spring) { step += 1 }
        } else {
            makePlan()
        }
    }

    private func makePlan() {
        isPlanning = true
        focusedStep = nil
        let answers = self.answers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let pomodoros = self.pomodoros
        let minutes = pomodoroMinutes
        // Only tie the session to the notebook workstream if Q1 is still its (unedited) name.
        let ws = workstream.flatMap { $0.goal == answers[0] ? $0 : nil }
        Task {
            let controller = FocusController.shared
            let plan = await controller.makePlan(answers: answers, pomodoros: pomodoros, pomodoroMinutes: minutes, workstream: ws)
            controller.start(plan: plan, answers: answers, pomodoros: pomodoros, pomodoroMinutes: minutes,
                             state: state, router: router)
            isPlanning = false
        }
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        if let ws = ActiveWorkstream.current() {
            workstream = ws
            if answers[0].isEmpty { answers[0] = ws.goal }
        }
    }
}
