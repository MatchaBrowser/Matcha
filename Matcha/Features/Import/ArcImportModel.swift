import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

/// A window's import from Arc (task 7.1): picking the `StorableSidebar.json` file, reading it, then the preview
/// (`request`) or the alert for an unreadable file. Only the user starts the import (File > Import From).
@MainActor
@Observable
final class ArcImportModel {
    /// Arc sidebar that was read, shown in the preview before the import.
    struct Request: Identifiable {
        let id = UUID()
        let sidebar: ArcSidebar
    }

    var request: Request?
    /// The chosen file is not an Arc sidebar.
    var isFailurePresented = false

    /// File to pick, reminded by the file picker and by the alert for an unreadable file.
    static let fileHint: LocalizedStringResource = .init(
        "Choose StorableSidebar.json, in Arc’s folder (~/Library/Application Support/Arc).",
        comment: "Open panel and error alert of the Arc import",
    )

    /// The user's Arc folder. The home folder comes from the system: in the sandbox,
    /// `homeDirectoryForCurrentUser` returns the app container's.
    static var arcFolder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)
    }

    /// Opens the file picker on the Arc folder, attached to `window` if there is one.
    func chooseFile(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.message = String(localized: Self.fileHint)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Arc keeps dated copies next to its file: this one is preselected if it exists.
        let file = Self.arcFolder.appending(path: "StorableSidebar.json")
        panel.directoryURL = FileManager.default.fileExists(atPath: file.path) ? file : Self.arcFolder
        Task {
            let response = if let window {
                await panel.beginSheetModal(for: window)
            } else {
                await panel.begin()
            }
            if response == .OK, let url = panel.url {
                open(url)
            }
        }
    }

    /// Largest file read: Arc's sidebar is a few megabytes at most.
    nonisolated static let maximumFileSize = 64 * 1024 * 1024

    /// Reads `url` off the main thread: the preview opens, or the alert (audit E7).
    func open(_ url: URL) {
        Task {
            do {
                let sidebar = try await Self.read(url)
                request = Request(sidebar: sidebar)
                Logger.imports.info("Barre d'Arc lue : \(sidebar.spaces.count, privacy: .public) Spaces")
            } catch {
                Logger.imports.error("Barre d'Arc illisible : \(error.logSummary, privacy: .public)")
                isFailurePresented = true
            }
        }
    }

    @concurrent
    private nonisolated static func read(_ url: URL) async throws -> ArcSidebar {
        guard try (url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= maximumFileSize else {
            throw ArcSidebarParser.Failure.unreadable
        }
        return try ArcSidebarParser.parse(Data(contentsOf: url))
    }
}
