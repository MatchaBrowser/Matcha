import Foundation

/// Élément de la section des épinglés : un onglet ou un dossier.
nonisolated enum PinnedItem: Equatable, Sendable, Identifiable {
    case tab(UUID)
    case folder(PinnedFolder)

    var id: UUID {
        switch self {
        case let .tab(id): id
        case let .folder(folder): folder.id
        }
    }

    /// Onglets de l'élément, dossiers compris, dans l'ordre d'affichage.
    var tabIDs: [UUID] {
        switch self {
        case let .tab(id): [id]
        case let .folder(folder): folder.items.flatMap(\.tabIDs)
        }
    }
}

/// Dossier de la section des épinglés ; il peut contenir des onglets et d'autres dossiers.
nonisolated struct PinnedFolder: Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var isCollapsed = false
    var items: [PinnedItem] = []
}

/// Opérations sur l'arbre des épinglés. Un dossier parent nil désigne la racine de la section.
nonisolated extension [PinnedItem] {
    /// Les mêmes éléments sans l'onglet `id`, où qu'il soit dans les dossiers.
    func removingTab(_ id: UUID) -> [PinnedItem] {
        compactMap { item in
            switch item {
            case let .tab(tabID):
                return tabID == id ? nil : item
            case var .folder(folder):
                folder.items = folder.items.removingTab(id)
                return .folder(folder)
            }
        }
    }

    /// Dossier parent et rang de l'élément `itemID` (onglet ou dossier).
    func location(of itemID: UUID, parent: UUID? = nil) -> (parent: UUID?, index: Int)? {
        for (index, item) in enumerated() {
            if item.id == itemID {
                return (parent, index)
            }
            if case let .folder(folder) = item, let found = folder.items.location(of: itemID, parent: folder.id) {
                return found
            }
        }
        return nil
    }

    /// Le dossier `folderID`, où qu'il soit.
    func folder(_ folderID: UUID) -> PinnedFolder? {
        for item in self {
            guard case let .folder(folder) = item else {
                continue
            }
            if folder.id == folderID {
                return folder
            }
            if let found = folder.items.folder(folderID) {
                return found
            }
        }
        return nil
    }

    /// Insère `item` dans le dossier `folderID` (nil : la racine) à `index`, borné.
    /// Renvoie faux si le dossier n'existe pas.
    @discardableResult
    mutating func insert(_ item: PinnedItem, inFolder folderID: UUID?, at index: Int) -> Bool {
        guard let folderID else {
            insert(item, at: Swift.min(Swift.max(index, 0), count))
            return true
        }
        return updateFolder(folderID) { folder in
            folder.items.insert(item, at: Swift.min(Swift.max(index, 0), folder.items.count))
        }
    }

    /// Applique `change` au dossier `folderID`, où qu'il soit. Renvoie faux s'il n'existe pas.
    @discardableResult
    mutating func updateFolder(_ folderID: UUID, _ change: (inout PinnedFolder) -> Void) -> Bool {
        for index in indices {
            guard case var .folder(folder) = self[index] else {
                continue
            }
            if folder.id == folderID {
                change(&folder)
                self[index] = .folder(folder)
                return true
            }
            if folder.items.updateFolder(folderID, change) {
                self[index] = .folder(folder)
                return true
            }
        }
        return false
    }

    /// Retire l'élément `itemID` (onglet ou dossier, avec son contenu) et le renvoie.
    mutating func removeItem(_ itemID: UUID) -> PinnedItem? {
        for index in indices {
            if self[index].id == itemID {
                return remove(at: index)
            }
            guard case var .folder(folder) = self[index], let removed = folder.items.removeItem(itemID) else {
                continue
            }
            self[index] = .folder(folder)
            return removed
        }
        return nil
    }
}
