import SwiftUI

/// Notes of the section chosen in the library, the most recently changed first: title, date and site of a linked
/// note. A double-click opens the note in a tab of the main window; its menu also opens the page, detaches the note,
/// moves it to a folder or deletes it (also the ⌫ key).
struct NotesLibraryList: View {
    let model: NotesLibraryModel
    /// Opens an address in a new tab of the main window: the page of a linked note, or the note itself (`NoteTab`).
    let openPage: (URL) -> Void

    var body: some View {
        List(selection: Binding(get: { model.selectedNoteID }, set: { model.select($0) })) {
            ForEach(model.notes) { note in
                row(note)
                    .tag(note.id)
            }
        }
        .accessibilityIdentifier("notesLibraryList")
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let note = model.notes.first(where: { $0.id == id }) {
                menu(for: note)
            }
        } primaryAction: { ids in
            // Double-click, Return: the note in a tab of the main window.
            ids.first.flatMap(NoteTab.url(for:)).map(openPage)
        }
        .onDeleteCommand {
            if let id = model.selectedNoteID {
                model.delete([id])
            }
        }
        .overlay {
            if model.notes.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.newNote()
                } label: {
                    Label(String(localized: "New Note", comment: "Notes library: toolbar button"), systemImage: "square.and.pencil")
                }
                .help(String(localized: "New Note"))
                .accessibilityIdentifier("newNoteButton")
            }
        }
    }

    private var placeholder: String {
        model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "No Notes", comment: "Notes library: the section chosen has no note")
            : String(localized: "No Results", comment: "Notes library: the search finds no note")
    }

    private func row(_ note: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? String(localized: "Untitled") : note.title)
                .font(.body.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(note.modifiedAt, format: .dateTime.day().month().year())
                if let link = note.link {
                    Text(verbatim: NotesLibrarySection.site(of: link))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func menu(for note: NoteSummary) -> some View {
        Button {
            NoteTab.url(for: note.id).map(openPage)
        } label: {
            Text("Open in New Tab", comment: "Notes panel and library menu: shows the note in a tab of its own")
        }
        Divider()
        if let link = note.link {
            Button {
                openPage(link.url)
            } label: {
                Text("Open Page", comment: "Notes library: opens the page of a linked note in a new tab")
            }
            Button {
                model.store.setLink(nil, of: note.id)
            } label: {
                Text("Detach from Page")
            }
            Divider()
        }
        Menu {
            Button {
                model.store.move(note.id, toFolder: nil)
            } label: {
                Text("No Folder", comment: "Notes library: “Move To” menu, the root of the library")
            }
            Divider()
            folderItems(note: note, parentID: nil, depth: 0)
        } label: {
            Text("Move To", comment: "Notes library: menu of the folders a note can go to")
        }
        Button {
            NoteExporter.export(note, store: model.store)
        } label: {
            Text("Export as Markdown…", comment: "Notes menus: saves the note as a Markdown file")
        }
        Divider()
        Button(role: .destructive) {
            model.delete([note.id])
        } label: {
            Text("Delete Note", comment: "Notes library: deletes a note")
        }
    }

    /// Folders of the profile, indented by depth.
    private func folderItems(note: NoteSummary, parentID: UUID?, depth: Int) -> AnyView {
        AnyView(ForEach(model.folders(in: parentID)) { folder in
            Button {
                model.store.move(note.id, toFolder: folder.id)
            } label: {
                Text(verbatim: String(repeating: "   ", count: depth) + folder.name)
            }
            .disabled(note.folderID == folder.id)
            folderItems(note: note, parentID: folder.id, depth: depth + 1)
        })
    }
}
