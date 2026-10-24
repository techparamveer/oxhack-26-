import SwiftUI

// Placeholder screens. Each feature step DELETES its placeholder from this file and
// adds a real `<Name>View.swift` with the same type name (so routing in SheepApp keeps working).

struct FocusIntakeView: View {
    var body: some View { PlaceholderScreen(title: "focus", note: "intake — step 3") }
}

struct FocusSessionView: View {
    var body: some View { PlaceholderScreen(title: "focus", note: "session — step 3") }
}

struct CongratsView: View {
    var body: some View { PlaceholderScreen(title: "done", note: "congrats — step 3") }
}

struct RestView: View {
    var body: some View { PlaceholderScreen(title: "rest", note: "step 5") }
}

struct PlayView: View {
    var body: some View { PlaceholderScreen(title: "play", note: "step 5") }
}

struct NotebookView: View {
    var body: some View { PlaceholderScreen(title: "notebook", note: "step 9") }
}

struct SetupView: View {
    var body: some View { PlaceholderScreen(title: "setup", note: "step 8") }
}

struct WrapperView: View {
    let app: WrappedApp
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PlaceholderScreen(title: app.title.lowercased(), note: "wrapper — step 2")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        TextButton(title: "close", color: Theme.text) { dismiss() }
                    }
                }
        }
    }
}

struct PlaceholderScreen: View {
    let title: String
    let note: String
    var body: some View {
        Screen(title: title) {
            Caption(note)
        }
    }
}
