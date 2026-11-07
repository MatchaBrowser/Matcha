import SwiftUI

/// Header of the notes panel: the note's title, its scope, the other actions (open in a tab, detach from the page,
/// delete), and the close button.
struct NotesPanelHeader: View {
    let model: NotesPanelModel
    /// Shows the note in a new tab of the window.
    let openInTab: (UUID) -> Void

    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        HStack(spacing: 6) {
            if let note = model.note {
                NoteTitleField(store: model.store, note: note)
                scopeMenu(note)
            } else {
                Text("Notes", comment: "Notes panel: title of the header when the page has no note")
                    .font(.headline)
                Spacer()
            }
            Button {
                withMotion(.easeInOut(duration: 0.2)) { model.close() }
            } label: {
                Label(String(localized: "Close Notes", comment: "Notes panel: tooltip of the close button"), systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .help(String(localized: "Close Notes"))
            .accessibilityIdentifier("closeNotesPanelButton")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 40)
        .confirmationDialog(
            Text("Delete this note?", comment: "Notes panel: question before deleting the note"),
            isPresented: $isDeleteConfirmationPresented,
        ) {
            Button(role: .destructive) {
                model.deleteNote()
            } label: {
                Text("Delete")
            }
        } message: {
            Text("You can't undo this action.", comment: "Notes panel: under the question before deleting the note")
        }
    }

    /// Scope of the note and the other actions.
    private func scopeMenu(_ note: NoteSummary) -> some View {
        Menu {
            Picker(selection: Binding(get: { note.link?.scope ?? .page }, set: { model.setScope($0) })) {
                Text("This Page Only", comment: "Notes panel menu: the note is linked to the page shown only").tag(NoteLinkScope.page)
                if let site = model.site {
                    Text("Every Page of \(site)", comment: "Notes panel menu: the note is shown on every page of a site; %@ is the site")
                        .tag(NoteLinkScope.site)
                }
            } label: {
                Text("Show the Note On", comment: "Notes panel menu: section title before the scope choices")
            }
            .pickerStyle(.inline)
            Divider()
            Button {
                openInTab(note.id)
            } label: {
                Text("Open in New Tab", comment: "Notes panel and library menu: shows the note in a tab of its own")
            }
            Button {
                NoteExporter.export(note, store: model.store)
            } label: {
                Text("Export as Markdown…", comment: "Notes menus: saves the note as a Markdown file")
            }
            Button {
                model.detachNote()
            } label: {
                Text("Detach from Page", comment: "Notes panel menu: the note stays in the library but leaves the page")
            }
            Button(role: .destructive) {
                isDeleteConfirmationPresented = true
            } label: {
                Text("Delete Note…", comment: "Notes panel menu: deletes the note after a confirmation")
            }
        } label: {
            Label(
                String(localized: "Note Options", comment: "Notes panel: tooltip of the menu of the note"),
                systemImage: "ellipsis.circle",
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Note Options"))
        .accessibilityIdentifier("noteOptionsMenu")
    }
}
