import Foundation

/// Dossiers d'épinglés.
extension TabManager {
    /// Crée un dossier en fin de `parent` (nil : racine des épinglés), déplie le parent et ouvre
    /// la saisie de son nom.
    @discardableResult
    func newFolder(in parent: UUID? = nil) -> UUID {
        if let parent {
            updateLayout { $0.setFolderCollapsed(parent, false) }
        }
        var id = UUID()
        updateLayout { id = $0.addFolder(named: String(localized: "New Folder"), in: parent) }
        renamingFolderID = id
        return id
    }

    /// Termine la saisie du nom ; un nom vide garde l'ancien.
    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            updateLayout { $0.renameFolder(id, to: trimmed) }
        }
        if renamingFolderID == id {
            renamingFolderID = nil
        }
    }

    func toggleFolder(_ id: UUID) {
        guard let folder = layout.pinned.folder(id) else {
            return
        }
        updateLayout { $0.setFolderCollapsed(id, !folder.isCollapsed) }
    }

    func moveFolder(_ id: UUID, to destination: SidebarDestination) {
        updateLayout { $0.moveFolder(id, to: destination) }
    }

    /// Supprime le dossier ; ses onglets et sous-dossiers prennent sa place.
    func deleteFolder(_ id: UUID) {
        updateLayout { $0.removeFolder(id) }
    }
}
