import SwiftUI

/// A note shown in a tab (task 12.5), in place of a page: its title, the page it is linked to, and its editor. The
/// editor exists only while the tab is shown (one web view per note on screen); the note is saved when it leaves.
struct NoteTabView: View {
    let tab: BrowserTab
    let noteID: UUID
    /// Makes this pane the active one (a click in a split).
    let activate: () -> Void

    @Environment(WindowModel.self) private var windowModel: WindowModel?
    @State private var editor: NoteEditor?

    var body: some View {
        if let windowModel, windowModel.session.notes.isPersistent {
            let store = windowModel.session.notes
            if let note = store.notes.first(where: { $0.id == noteID }) {
                VStack(spacing: 0) {
                    header(note, store: store, tabManager: windowModel.tabManager)
                    Divider()
                    NoteSyncBanner(note: note)
                    if let editor {
                        NoteEditorView(editor: editor)
                            .id(ObjectIdentifier(editor))
                    } else {
                        Color.clear
                    }
                }
                .simultaneousGesture(TapGesture().onEnded { activate() })
                .onAppear { start(store: store, tabManager: windowModel.tabManager) }
                .onDisappear { stop() }
            } else {
                unavailable(Text("This note was deleted.", comment: "Tab of a note that no longer exists"))
            }
        } else {
            unavailable(Text("Notes aren't kept in private windows.", comment: "Tab of a note in a private window"))
        }
    }

    private func header(_ note: NoteSummary, store: NoteStore, tabManager: TabManager) -> some View {
        HStack(spacing: 8) {
            NoteTitleField(store: store, note: note, font: .title3.weight(.semibold))
            if let link = note.link {
                Button {
                    _ = tabManager.newTab(url: link.url)
                } label: {
                    Label(NotesLibrarySection.site(of: link), systemImage: link.scope == .site ? "globe" : "link")
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                .help(String(localized: "Open Page", comment: "Notes library: opens the page of a linked note in a new tab"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func unavailable(_ text: Text) -> some View {
        ContentUnavailableView {
            Label { text } icon: { Image(systemName: "doc.text") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func start(store: NoteStore, tabManager: TabManager) {
        let editor = editor ?? NoteEditor(store: store)
        editor.openLink = { url in _ = tabManager.newTab(url: url) }
        self.editor = editor
        Task { await editor.open(noteID) }
    }

    private func stop() {
        let editor = editor
        self.editor = nil
        Task { await editor?.flush() }
    }
}
