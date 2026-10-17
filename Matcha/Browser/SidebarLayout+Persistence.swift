import Foundation

/// Position d'un onglet dans la barre, telle qu'enregistrée.
nonisolated struct SidebarPosition: Equatable, Sendable {
    var place: TabPlace
    /// Rang dans son conteneur : favoris, racine des épinglés ou dossier, onglets du jour.
    var order: Int
    /// Dossier qui contient l'onglet épinglé, nil à la racine.
    var folderID: UUID?
}

/// Dossier d'épinglés tel qu'enregistré.
nonisolated struct FolderEntry: Equatable, Sendable {
    var id: UUID
    var name: String
    var isCollapsed: Bool
    /// Dossier parent, nil à la racine des épinglés.
    var parentID: UUID?
    /// Rang dans son conteneur, sur la même échelle que les onglets.
    var order: Int
}

/// Passage du rangement en mémoire à sa forme enregistrée (positions à plat), et retour.
nonisolated extension SidebarLayout {
    /// Position de chaque onglet rangé.
    var positions: [UUID: SidebarPosition] {
        var result: [UUID: SidebarPosition] = [:]
        for (order, id) in favorites.enumerated() {
            result[id] = SidebarPosition(place: .favorite, order: order)
        }
        for (order, id) in today.enumerated() {
            result[id] = SidebarPosition(place: .today, order: order)
        }
        Self.collectPinned(pinned, in: nil, positions: &result)
        return result
    }

    /// Dossiers d'épinglés, avec leur parent et leur rang.
    var folderEntries: [FolderEntry] {
        var result: [FolderEntry] = []
        Self.collectFolders(pinned, in: nil, entries: &result)
        return result
    }

    /// Reconstruit le rangement : chaque conteneur dans l'ordre croissant des rangs. Un dossier dont le
    /// parent est inconnu, ou pris dans une boucle, va à la racine ; un épinglé dans un dossier inconnu aussi.
    init(positions: [UUID: SidebarPosition], folders: [FolderEntry]) {
        self.init()
        for (id, _) in positions.filter({ $0.value.place == .favorite }).sorted(by: Self.byOrder) {
            setPlace(id, to: .favorite)
        }
        for (id, _) in positions.filter({ $0.value.place == .today }).sorted(by: Self.byOrder) {
            insertToday(id, at: today.count)
        }
        let knownFolders = Set(folders.map(\.id))
        var pinnedTabs = positions.filter { $0.value.place == .pinned }
        for (id, position) in pinnedTabs where position.folderID.map({ !knownFolders.contains($0) }) ?? false {
            pinnedTabs[id]?.folderID = nil
        }
        var remaining = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        for (id, entry) in remaining where entry.parentID.map({ !knownFolders.contains($0) }) ?? false {
            remaining[id]?.parentID = nil
        }
        fillPinned(in: nil, tabs: pinnedTabs, folders: &remaining)
        // Dossiers pris dans une boucle de parents : jamais atteints depuis la racine. Les épinglés de la
        // racine sont déjà placés ; seuls ceux des dossiers restent à ranger.
        let tabsInFolders = pinnedTabs.filter { $0.value.folderID != nil }
        while let orphan = remaining.values.min(by: { $0.order < $1.order }) {
            remaining[orphan.id]?.parentID = nil
            fillPinned(in: nil, tabs: tabsInFolders, folders: &remaining)
        }
    }

    /// Ajoute, dans l'ordre des rangs, les onglets et dossiers de `parent`, puis le contenu de chaque dossier.
    /// Chaque dossier placé est retiré de `folders`.
    private mutating func fillPinned(in parent: UUID?, tabs: [UUID: SidebarPosition], folders: inout [UUID: FolderEntry]) {
        enum Item { case tab(UUID), folder(FolderEntry) }
        let children = tabs.filter { $0.value.folderID == parent }.map { (order: $0.value.order, item: Item.tab($0.key)) }
            + folders.values.filter { $0.parentID == parent }.map { (order: $0.order, item: Item.folder($0)) }
        for child in children.sorted(by: { $0.order < $1.order }) {
            switch child.item {
            case let .tab(id):
                setPlace(id, to: .pinned)
                move(id, to: .pinned(folder: parent, index: Int.max))
            case let .folder(entry):
                folders[entry.id] = nil
                addFolder(id: entry.id, named: entry.name, in: parent)
                setFolderCollapsed(entry.id, entry.isCollapsed)
                fillPinned(in: entry.id, tabs: tabs, folders: &folders)
            }
        }
    }

    private static func collectPinned(_ items: [PinnedItem], in folder: UUID?, positions: inout [UUID: SidebarPosition]) {
        for (order, item) in items.enumerated() {
            switch item {
            case let .tab(id):
                positions[id] = SidebarPosition(place: .pinned, order: order, folderID: folder)
            case let .folder(child):
                collectPinned(child.items, in: child.id, positions: &positions)
            }
        }
    }

    private static func collectFolders(_ items: [PinnedItem], in parent: UUID?, entries: inout [FolderEntry]) {
        for (order, item) in items.enumerated() {
            guard case let .folder(folder) = item else {
                continue
            }
            entries.append(FolderEntry(id: folder.id, name: folder.name, isCollapsed: folder.isCollapsed, parentID: parent, order: order))
            collectFolders(folder.items, in: folder.id, entries: &entries)
        }
    }

    private static func byOrder(_ lhs: (key: UUID, value: SidebarPosition), _ rhs: (key: UUID, value: SidebarPosition)) -> Bool {
        lhs.value.order < rhs.value.order
    }
}
