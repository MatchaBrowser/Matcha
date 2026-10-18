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

    /// Donne au dossier `appearance` (icône, couleurs), telle qu'elle sera enregistrée (`FolderAppearance.normalized`).
    /// Sans effet si rien ne change : pas d'enregistrement inutile pendant qu'on glisse dans le sélecteur de couleur.
    func setFolderAppearance(_ id: UUID, _ appearance: FolderAppearance) {
        let normalized = appearance.normalized
        guard let folder = layout.pinned.folder(id), folder.appearance != normalized else {
            return
        }
        updateLayout { $0.setFolderAppearance(id, normalized) }
    }

    /// Applique `change` à l'apparence actuelle du dossier (panneau de personnalisation).
    func updateFolderAppearance(_ id: UUID, _ change: (inout FolderAppearance) -> Void) {
        guard var appearance = layout.pinned.folder(id)?.appearance else {
            return
        }
        change(&appearance)
        setFolderAppearance(id, appearance)
    }
}
