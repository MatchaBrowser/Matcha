import SwiftUI

/// Notes panel of a window (task 12.3), to the right of the card: the note of the page shown in its editor, or an
/// invitation to write one. Its header gives the title, the scope (this page or the whole site) and the other actions.
struct NotesPanel: View {
    let model: NotesPanelModel

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        VStack(spacing: 0) {
            NotesPanelHeader(model: model) { id in
                if let url = NoteTab.url(for: id) {
                    windowModel?.tabManager.newTab(url: url)
                }
            }
            Divider()
            content
        }
        .pageCardFrame(cornerRadius: BrowserWindowView.cardCornerRadius)
        // A note made, deleted or detached elsewhere (library, another window): the editor follows.
        .onChange(of: model.note?.id, initial: true) { model.showNote() }
        // The links of the note open in a new tab of the window.
        .onChange(of: model.editor.map(ObjectIdentifier.init), initial: true) {
            // Weak: the window's model holds the panel, which holds the editor.
            let window = windowModel
            model.editor?.openLink = { [weak window] url in
                window?.tabManager.newTab(url: url)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notes", comment: "VoiceOver label of the notes panel"))
        .accessibilityIdentifier("notesPanel")
    }

    @ViewBuilder private var content: some View {
        if !model.canLink {
            placeholder(
                Text("Notes can only be linked to web pages.", comment: "Notes panel: the page shown is not a website"),
            )
        } else if model.note == nil {
            emptyPage
        } else if let editor = model.editor {
            VStack(spacing: 0) {
                banner(for: editor.state)
                if let note = model.note {
                    NoteSyncBanner(note: note)
                }
                NoteEditorView(editor: editor)
                    .id(ObjectIdentifier(editor))
            }
        }
    }

    /// No note for this page: one for the page, or one for its whole site.
    private var emptyPage: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Note for This Page", comment: "Notes panel: title when the page shown has no note")
                .font(.headline)
            Button {
                model.createNote(scope: .page)
            } label: {
                Text("Add a Note to This Page", comment: "Notes panel: button that makes a note linked to the page shown")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("addPageNoteButton")
            if let site = model.site {
                Button {
                    model.createNote(scope: .site)
                } label: {
                    Text(
                        "Add a Note to \(site)",
                        comment: "Notes panel: button that makes a note for every page of a website; %@ is the site (example.com)",
                    )
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("addSiteNoteButton")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Why the note can't be changed or saved, above it.
    @ViewBuilder private func banner(for state: NoteEditor.State) -> some View {
        switch state {
        case .unreadable:
            bannerText(Text(
                "This note was written by a newer version of Matcha. It can't be changed here.",
                comment: "Notes panel: banner above a note this version can't read (shown read-only)",
            ))
        case .tooLarge:
            bannerText(Text(
                "This note is too long to be saved. Shorten it to save your changes.",
                comment: "Notes panel: banner above a note larger than the store takes",
            ))
        case .empty, .loading, .editing:
            EmptyView()
        }
    }

    private func bannerText(_ text: Text) -> some View {
        text
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.18))
    }
}
