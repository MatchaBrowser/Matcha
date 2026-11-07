import SwiftUI

/// Sidebar of the notes library: all the notes, the page notes by site, then the folders, which can be made, renamed,
/// nested and deleted.
struct NotesLibrarySidebar: View {
    @Bindable var model: NotesLibraryModel

    /// Folder being named (new or renamed), and its name being typed.
    @State private var naming: Naming?
    @State private var name = ""
    @State private var deletedFolder: NoteFolder?

    private enum Naming {
        case new
        case rename(NoteFolder)
    }

    var body: some View {
        List(selection: $model.section) {
            Section {
                Label { Text("All Notes", comment: "Notes library sidebar") } icon: { Image(systemName: "tray.full") }
                    .tag(NotesLibrarySection.all)
                Label { Text("Page Notes", comment: "Notes library sidebar: notes linked to a page or a site") } icon: {
                    Image(systemName: "globe")
                }
                .tag(NotesLibrarySection.pageNotes)
                ForEach(model.sites, id: \.self) { site in
                    Label(site, systemImage: "link")
                        .padding(.leading, 12)
                        .tag(NotesLibrarySection.site(site))
                }
            }
            Section {
                folderRows(in: nil)
            } header: {
                Text("Folders", comment: "Notes library sidebar: section of the folders")
            }
        }
        .accessibilityIdentifier("notesLibrarySidebar")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    name = String(localized: "New Folder", comment: "Default name of a new folder of notes")
                    naming = .new
                } label: {
                    Label(String(localized: "New Folder"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "New Folder"))
                .accessibilityIdentifier("newNoteFolderButton")
                Spacer()
                Button {
                    NoteExporter.exportAll(store: model.store, profileID: model.profileID)
                } label: {
                    Label(
                        String(localized: "Export All Notes…", comment: "Notes library: writes every note as Markdown files into a folder"),
                        systemImage: "square.and.arrow.up",
                    )
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(String(localized: "Export All Notes…"))
                .accessibilityIdentifier("exportAllNotesButton")
            }
            .padding(8)
        }
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: {
            if !$0 {
                naming = nil
            }
        })) {
            TextField(text: $name) { Text("Name", comment: "Field of the name of a folder of notes") }
            Button("OK") { commitName() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            Text("Delete this folder and its notes?", comment: "Notes library: question before deleting a folder"),
            isPresented: Binding(get: { deletedFolder != nil }, set: {
                if !$0 {
                    deletedFolder = nil
                }
            }),
        ) {
            Button(role: .destructive) {
                if let deletedFolder {
                    model.deleteFolder(deletedFolder.id)
                }
            } label: {
                Text("Delete")
            }
        } message: {
            Text(
                "Its subfolders and all their notes are deleted too. You can't undo this action.",
                comment: "Notes library: under the question before deleting a folder",
            )
        }
    }

    /// Folders under `parentID`, each with its subfolders below it.
    private func folderRows(in parentID: UUID?) -> AnyView {
        AnyView(ForEach(model.folders(in: parentID)) { folder in
            let children = model.folders(in: folder.id)
            Group {
                if children.isEmpty {
                    folderLabel(folder)
                } else {
                    DisclosureGroup {
                        folderRows(in: folder.id)
                    } label: {
                        folderLabel(folder)
                    }
                }
            }
        })
    }

    private func folderLabel(_ folder: NoteFolder) -> some View {
        Label(folder.name, systemImage: "folder")
            .tag(NotesLibrarySection.folder(folder.id))
            .contextMenu {
                Button {
                    model.section = .folder(folder.id)
                    model.newNote()
                } label: {
                    Text("New Note", comment: "Notes library: toolbar button")
                }
                Divider()
                Button {
                    name = folder.name
                    naming = .rename(folder)
                } label: {
                    Text("Rename…")
                }
                Button {
                    model.store.moveFolder(folder.id, toParent: nil)
                } label: {
                    Text("Move to Top Level", comment: "Notes library: moves a subfolder to the root of the folders")
                }
                .disabled(folder.parentID == nil)
                Divider()
                Button(role: .destructive) {
                    deletedFolder = folder
                } label: {
                    Text("Delete Folder…", comment: "Notes library: deletes a folder after a confirmation")
                }
            }
    }

    private var namingTitle: Text {
        switch naming {
        case .rename: Text("Rename Folder", comment: "Notes library: title of the alert that renames a folder")
        case .new, nil: Text("New Folder")
        }
    }

    private func commitName() {
        switch naming {
        case .new:
            if let folder = model.newFolder(named: name) {
                model.section = .folder(folder.id)
            }
        case let .rename(folder):
            model.store.renameFolder(folder.id, to: name)
        case nil:
            break
        }
        naming = nil
    }
}
