import SwiftUI

/// One memory file: rendered body (YAML header hidden), edit the raw file, or delete it.
struct NotebookFileView: View {
    let path: String

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var draft = ""
    @State private var isEditing = false
    @State private var confirmingDelete = false
    @FocusState private var editorFocused: Bool

    private var document: MemoryDocument { MemoryDocument(content) }
    private var isSafe: Bool { NotebookModel.isSafeMemoryPath(path) }

    var body: some View {
        Screen(title: NotebookModel.title(path: path, document: document)) {
            VStack(alignment: .leading, spacing: 0) {
                if !isSafe {
                    Caption("This note isn't available.")
                        .padding(.vertical, Theme.space(2))
                    Spacer()
                } else {
                    if isEditing { editor } else { reader }
                    Hairline()
                    actions
                        .padding(.vertical, Theme.space(1))
                }
            }
        }
        .onAppear {
            content = isSafe ? (MemoryStore.shared.read(path) ?? "") : ""
        }
        .animation(Theme.spring, value: isEditing)
        .animation(Theme.spring, value: confirmingDelete)
    }

    // MARK: Read

    private var reader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space(1)) {
                Caption([path, document.updated.map { "updated \(NotebookModel.formatUpdated($0))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .padding(.bottom, Theme.space(1))
                let blocks = MarkdownBlock.parse(document.body)
                if blocks.isEmpty {
                    Caption("This note is empty.")
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.space(2))
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Edit

    private var editor: some View {
        TextEditor(text: $draft)
            .font(Theme.nunito(15, weight: 500, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($editorFocused)
            .padding(.vertical, Theme.space(1))
            .padding(.horizontal, -5) // TextEditor's built-in inset → align text with the 24 pt margin
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        if isEditing {
            VStack(spacing: Theme.space(1)) {
                PrimaryButton(title: "save") { save() }
                TextButton(title: "cancel") {
                    editorFocused = false
                    isEditing = false
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.space(1))
        } else if confirmingDelete {
            VStack(alignment: .leading, spacing: 0) {
                Caption("Delete this note? Sheep will forget it.")
                    .padding(.top, Theme.space(1))
                HStack {
                    TextButton(title: "keep it", color: Theme.text) { confirmingDelete = false }
                    Spacer()
                    TextButton(title: "delete for good", color: Theme.scoreDown) { delete() }
                }
            }
        } else {
            HStack {
                TextButton(title: "edit", color: Theme.text) {
                    draft = content
                    isEditing = true
                }
                Spacer()
                TextButton(title: "delete", color: Theme.scoreDown) { confirmingDelete = true }
            }
        }
    }

    private func save() {
        guard isSafe else { return }
        MemoryStore.shared.write(path, content: draft)
        content = MemoryStore.shared.read(path) ?? draft
        editorFocused = false
        isEditing = false
    }

    private func delete() {
        guard isSafe else { return }
        MemoryStore.shared.delete(path)
        dismiss()
    }
}

/// Renders one line-level markdown block in Nunito, with inline **bold** / *italic*.
struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text, size: level == 1 ? 20 : 17, weight: 800))
                .foregroundStyle(Theme.text)
                .padding(.top, Theme.space(level == 1 ? 1 : 0.5))
        case .bullet(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.space(1)) {
                Text("•").font(Theme.body).foregroundStyle(Theme.secondary)
                Text(Self.inline(text, size: 17, weight: 500)).foregroundStyle(Theme.bodyText)
            }
            .padding(.leading, Theme.space(2) * CGFloat(indent))
        case .paragraph(let text):
            Text(Self.inline(text, size: 17, weight: 500)).foregroundStyle(Theme.bodyText)
        case .spacer:
            Color.clear.frame(height: Theme.space(0.5))
        }
    }

    /// Inline markdown with every run set to an explicit Nunito weight (no system bold fallback).
    static func inline(_ text: String, size: CGFloat, weight: CGFloat) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var out = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let runs = out.runs.map { ($0.range, $0.inlinePresentationIntent ?? []) }
        for (range, intent) in runs {
            let bold = intent.contains(.stronglyEmphasized)
            let italic = intent.contains(.emphasized)
            out[range].font = Theme.nunito(size, weight: bold ? max(weight, 800) : weight,
                                           italic: italic, relativeTo: .body)
            out[range].inlinePresentationIntent = nil
        }
        return out
    }
}
