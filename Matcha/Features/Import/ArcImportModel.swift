import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

/// Import depuis Arc d'une fenêtre (tâche 7.1) : choix du fichier `StorableSidebar.json`, lecture, puis l'aperçu
/// (`request`) ou l'alerte d'un fichier illisible. Seul l'utilisateur lance l'import (Fichier > Importer depuis).
@MainActor
@Observable
final class ArcImportModel {
    /// Barre d'Arc lue, montrée dans l'aperçu avant l'import.
    struct Request: Identifiable {
        let id = UUID()
        let sidebar: ArcSidebar
    }

    var request: Request?
    /// Le fichier choisi n'est pas une barre d'Arc.
    var isFailurePresented = false

    /// Fichier à choisir, rappelé par le sélecteur et par l'alerte d'un fichier illisible.
    static let fileHint: LocalizedStringResource = .init(
        "Choose StorableSidebar.json, in Arc’s folder (~/Library/Application Support/Arc).",
        comment: "Open panel and error alert of the Arc import",
    )

    /// Dossier d'Arc de l'utilisateur. Le dossier personnel vient du système : dans le bac à sable,
    /// `homeDirectoryForCurrentUser` donne celui du conteneur de l'app.
    static var arcFolder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)
    }

    /// Ouvre le sélecteur de fichier sur le dossier d'Arc, attaché à `window` s'il y en a une.
    func chooseFile(in window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.message = String(localized: Self.fileHint)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Arc garde des copies datées à côté de son fichier : celui-ci est présélectionné s'il existe.
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

    /// Lit `url` : l'aperçu s'ouvre, ou l'alerte.
    func open(_ url: URL) {
        do {
            let sidebar = try ArcSidebarParser.parse(Data(contentsOf: url))
            request = Request(sidebar: sidebar)
            Logger.imports.info("Barre d'Arc lue : \(sidebar.spaces.count, privacy: .public) Spaces")
        } catch {
            Logger.imports.error("Barre d'Arc illisible : \(String(describing: error), privacy: .public)")
            isFailurePresented = true
        }
    }
}
