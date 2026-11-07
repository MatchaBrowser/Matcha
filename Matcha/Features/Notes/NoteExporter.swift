import AppKit
import OSLog
import UniformTypeIdentifiers

/// “Export as Markdown…” of a note, and “Export All Notes…” of a profile into a folder (task 12.9).
@MainActor
enum NoteExporter {
    private static var markdownType: UTType {
        UTType("net.daringfireball.markdown") ?? .plainText
    }

    /// Asks where to save the note, then writes it.
    static func export(_ note: NoteSummary, store: NoteStore) {
        guard let content = store.content(of: note.id),
              let markdown = NoteMarkdown.markdown(title: note.title, content: content, link: note.link)
        else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [markdownType]
        panel.nameFieldStringValue = NoteExportPlan.safeName(note.title) + ".md"
        Task {
            guard await panel.begin() == .OK, let destination = panel.url else {
                return
            }
            do {
                try PageExportFile.write(Data(markdown.utf8), to: destination)
                Logger.notes.info("Note exported (\(markdown.utf8.count, privacy: .public) bytes)")
            } catch {
                Logger.notes.error("Note not exported: \(error.logSummary, privacy: .public)")
                NSSound.beep()
            }
        }
    }

    /// Asks for a folder, then writes every note of the profile in it.
    static func exportAll(store: NoteStore, profileID: UUID?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Export", comment: "Button of the folder chooser of “Export All Notes…”")
        Task {
            guard await panel.begin() == .OK, let root = panel.url else {
                return
            }
            let documents = store.notes(ofProfile: profileID).compactMap { note in
                store.content(of: note.id).map { (note: note, content: $0) }
            }
            let files = NoteExportPlan.files(
                for: documents,
                folders: store.folders.filter { $0.profileID == profileID },
                pageNotesName: String(localized: "Page Notes", comment: "Notes library sidebar: notes linked to a page or a site"),
            )
            var written = 0
            for file in files {
                let destination = file.path.reduce(root) { $0.appendingPathComponent($1) }
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try PageExportFile.write(Data(file.markdown.utf8), to: destination)
                    written += 1
                } catch {
                    Logger.notes.error("Note not exported: \(error.logSummary, privacy: .public)")
                }
            }
            Logger.notes.info("\(written, privacy: .public) of \(files.count, privacy: .public) notes exported")
            if written < files.count {
                NSSound.beep()
            }
        }
    }
}
