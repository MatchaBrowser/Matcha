import Foundation

/// Item of the pinned section: a tab or a folder.
nonisolated enum PinnedItem: Equatable, Sendable, Identifiable {
    case tab(UUID)
    case folder(PinnedFolder)

    var id: UUID {
        switch self {
        case let .tab(id): id
        case let .folder(folder): folder.id
        }
    }

    /// Tabs of the item, folders included, in display order.
    var tabIDs: [UUID] {
        switch self {
        case let .tab(id): [id]
        case let .folder(folder): folder.items.flatMap(\.tabIDs)
        }
    }
}

/// Folder of the pinned section; it can contain tabs and other folders.
nonisolated struct PinnedFolder: Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var isCollapsed = false
    var items: [PinnedItem] = []
    /// Icon and colors chosen in its customization panel.
    var appearance = FolderAppearance()
}

/// Operations on the tree of pinned tabs. A nil parent folder designates the root of the section.
nonisolated extension [PinnedItem] {
    /// The same items without the tab `id`, wherever it is in the folders.
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

    /// Parent folder and position of the item `itemID` (tab or folder).
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

    /// The folder `folderID`, wherever it is.
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

    /// Inserts `item` into the folder `folderID` (nil: the root) at `index`, clamped.
    /// Returns false if the folder does not exist.
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

    /// Applies `change` to the folder `folderID`, wherever it is. Returns false if it does not exist.
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

    /// Removes the item `itemID` (tab or folder, with its content) and returns it.
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
