import Foundation

/// Folders of pinned tabs.
extension TabManager {
    /// Creates a folder at the end of `parent` (nil: root of the pinned tabs), expands the parent and starts
    /// editing its name.
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

    /// Ends the name editing; an empty name keeps the old one.
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

    /// Moves the folder one step up (−1) or down (+1) among its neighbors, without dragging (audit H3); false at the
    /// edge.
    @discardableResult
    func moveFolderStep(_ id: UUID, by offset: Int) -> Bool {
        guard let destination = layout.stepDestination(of: id, by: offset) else {
            return false
        }
        moveFolder(id, to: destination)
        return true
    }

    /// Deletes the folder; its tabs and subfolders take its place.
    func deleteFolder(_ id: UUID) {
        updateLayout { $0.removeFolder(id) }
    }

    /// Gives the folder `appearance` (icon, colors), as it will be saved (`FolderAppearance.normalized`).
    /// No effect if nothing changes: no needless saving while dragging in the color picker.
    func setFolderAppearance(_ id: UUID, _ appearance: FolderAppearance) {
        let normalized = appearance.normalized
        guard let folder = layout.pinned.folder(id), folder.appearance != normalized else {
            return
        }
        updateLayout { $0.setFolderAppearance(id, normalized) }
    }

    /// Applies `change` to the folder's current appearance (customization panel).
    func updateFolderAppearance(_ id: UUID, _ change: (inout FolderAppearance) -> Void) {
        guard var appearance = layout.pinned.folder(id)?.appearance else {
            return
        }
        change(&appearance)
        setFolderAppearance(id, appearance)
    }
}
