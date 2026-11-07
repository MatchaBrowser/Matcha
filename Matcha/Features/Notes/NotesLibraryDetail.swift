import SwiftUI

/// Note chosen in the library: its title, the page it is linked to (opened in the main window), and its editor.
struct NotesLibraryDetail: View {
    let model: NotesLibraryModel
    let openPage: (URL) -> Void

    var body: some View {
        if let note = model.selectedNote, let editor = model.editor {
            VStack(spacing: 0) {
                header(note)
                Divider()
                NoteSyncBanner(note: note)
                NoteEditorView(editor: editor)
                    .id(ObjectIdentifier(editor))
            }
        } else {
            Text("No Note Selected", comment: "Notes library: no note is chosen in the list")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ note: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NoteTitleField(store: model.store, note: note, font: .title2.weight(.semibold))
            if let link = note.link {
                Button {
                    openPage(link.url)
                } label: {
                    Label(link.title ?? link.url.absoluteString, systemImage: link.scope == .site ? "globe" : "link")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
                .help(String(localized: "Open Page"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
