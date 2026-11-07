import Foundation

/// Files of “Export All Notes…” (task 12.9): one Markdown file per note, in folders like the library's; the linked notes
/// in a “Page Notes” folder, by site. Names made safe for a file, and unique in their folder. Pure type.
nonisolated enum NoteExportPlan {
    struct File: Equatable, Sendable {
        /// Path relative to the folder chosen, folders included.
        let path: [String]
        let markdown: String
    }

    /// `documents`: each note with its document; a document that can't be read is left out.
    static func files(for documents: [(note: NoteSummary, content: String)], folders: [NoteFolder], pageNotesName: String) -> [File] {
        let byID = Dictionary(folders.map { ($0.id, $0) }) { first, _ in first }
        var taken: [String: Set<String>] = [:]
        var files: [File] = []
        for (note, content) in documents {
            guard let markdown = NoteMarkdown.markdown(title: note.title, content: content, link: note.link) else {
                continue
            }
            let directory = if let link = note.link {
                [safeName(pageNotesName), safeName(NotesLibrarySection.site(of: link))]
            } else {
                folderPath(of: note.folderID, in: byID)
            }
            let key = directory.joined(separator: "/")
            let name = uniqueName(note.title, among: taken[key, default: []])
            taken[key, default: []].insert(name.lowercased())
            files.append(File(path: directory + [name], markdown: markdown))
        }
        return files
    }

    /// Names of the folders from the root down to `id`; stops on a cycle.
    private static func folderPath(of id: UUID?, in folders: [UUID: NoteFolder]) -> [String] {
        var names: [String] = []
        var seen: Set<UUID> = []
        var current = id
        while let folderID = current, let folder = folders[folderID], seen.insert(folderID).inserted {
            names.insert(safeName(folder.name), at: 0)
            current = folder.parentID
        }
        return names
    }

    /// “<title>.md”, followed by a number if the folder already has that name.
    private static func uniqueName(_ title: String, among taken: Set<String>) -> String {
        let base = safeName(title)
        var name = base + ".md"
        var number = 2
        while taken.contains(name.lowercased()) {
            name = "\(base) \(number).md"
            number += 1
        }
        return name
    }

    /// A name that can't cut a path or hide the file: no “/”, “\” or “:”, no leading dot, 100 characters at most.
    static func safeName(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .filter { !$0.isNewline && $0 != "\0" }
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        let name = String(cleaned.prefix(100))
        return name.isEmpty ? String(localized: "Untitled", comment: "Placeholder of a note's empty title") : name
    }
}
