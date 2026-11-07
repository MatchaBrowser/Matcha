import SwiftUI

/// Title of a note, changed in place: saved on Return or when the field loses focus, not at each keystroke (a new title
/// moves the note to the top of the lists). Follows a change made elsewhere while it isn't being edited.
struct NoteTitleField: View {
    let store: NoteStore
    let note: NoteSummary
    var font = Font.headline

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(text: $title, prompt: Text("Untitled", comment: "Placeholder of a note's empty title")) {
            Text("Title", comment: "Notes panel: label of the note's title field")
        }
        .textFieldStyle(.plain)
        .font(font)
        .focused($isFocused)
        .onSubmit { commit() }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commit()
            }
        }
        .onChange(of: note.id, initial: true) { title = note.title }
        .onChange(of: note.title) { _, saved in
            if !isFocused {
                title = saved
            }
        }
        .accessibilityIdentifier("noteTitleField")
    }

    private func commit() {
        if title != note.title {
            store.rename(note.id, to: title)
        }
    }
}
