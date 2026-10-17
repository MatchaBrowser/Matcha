import Foundation

/// Place d'un onglet dans la barre latérale.
nonisolated enum TabPlace: String, CaseIterable, Sendable {
    case favorite
    case pinned
    case today
}

/// Endroit où déposer un onglet : une section (ou un dossier d'épinglés) et un rang dans celle-ci.
/// Le rang se lit avant le déplacement : déposer « avant l'élément n° i » donne `index: i`.
nonisolated enum SidebarDestination: Equatable, Sendable {
    case favorites(index: Int)
    /// Épinglés : à la racine (`folder` nil) ou dans un dossier.
    case pinned(folder: UUID?, index: Int)
    case today(index: Int)

    var index: Int {
        switch self {
        case let .favorites(index), let .pinned(_, index), let .today(index): index
        }
    }
}

/// Rangement des onglets dans la barre latérale : favoris, épinglés (avec dossiers), onglets du jour.
/// Type pur : il ne connaît que les identifiants des onglets.
nonisolated struct SidebarLayout: Equatable, Sendable {
    private(set) var favorites: [UUID] = []
    private(set) var pinned: [PinnedItem] = []
    private(set) var today: [UUID] = []

    /// Tous les onglets dans l'ordre de la barre : favoris, épinglés (dossiers compris), puis du jour.
    var orderedTabIDs: [UUID] {
        favorites + pinned.flatMap(\.tabIDs) + today
    }

    func place(of id: UUID) -> TabPlace? {
        if favorites.contains(id) {
            return .favorite
        }
        if today.contains(id) {
            return .today
        }
        if pinned.contains(where: { $0.tabIDs.contains(id) }) {
            return .pinned
        }
        return nil
    }

    /// Place l'onglet parmi ceux du jour, à `index` (borné), en le retirant d'ailleurs.
    mutating func insertToday(_ id: UUID, at index: Int) {
        remove(id)
        today.insert(id, at: Self.clamp(index, count: today.count))
    }

    /// Change la place de l'onglet : en fin de favoris ou d'épinglés, ou en tête des onglets du jour.
    /// Sans effet s'il y est déjà.
    mutating func setPlace(_ id: UUID, to place: TabPlace) {
        guard self.place(of: id) != place else {
            return
        }
        remove(id)
        switch place {
        case .favorite: favorites.append(id)
        case .pinned: pinned.append(.tab(id))
        case .today: today.insert(id, at: 0)
        }
    }

    /// Déplace un onglet déjà rangé vers `destination` (glisser-déposer). Un dossier inconnu
    /// renvoie l'onglet à la fin des épinglés.
    mutating func move(_ id: UUID, to destination: SidebarDestination) {
        guard place(of: id) != nil else {
            return
        }
        var index = destination.index
        // Dans le même conteneur, retirer l'onglet décale d'un cran les rangs qui le suivent.
        if let source = container(of: id), source.container == Container(destination), source.index < index {
            index -= 1
        }
        remove(id)
        switch destination {
        case .favorites:
            favorites.insert(id, at: Self.clamp(index, count: favorites.count))
        case .today:
            today.insert(id, at: Self.clamp(index, count: today.count))
        case let .pinned(folder, _):
            if !pinned.insert(.tab(id), inFolder: folder, at: index) {
                pinned.append(.tab(id))
            }
        }
    }

    /// Crée un dossier d'épinglés vide dans `parent` (nil : la racine), à `index` ou à la fin.
    @discardableResult
    mutating func addFolder(id: UUID = UUID(), named name: String, in parent: UUID? = nil, at index: Int? = nil) -> UUID {
        let folder = PinnedFolder(id: id, name: name)
        if !pinned.insert(.folder(folder), inFolder: parent, at: index ?? Int.max) {
            pinned.append(.folder(folder))
        }
        return folder.id
    }

    mutating func renameFolder(_ id: UUID, to name: String) {
        pinned.updateFolder(id) { $0.name = name }
    }

    mutating func setFolderCollapsed(_ id: UUID, _ isCollapsed: Bool) {
        pinned.updateFolder(id) { $0.isCollapsed = isCollapsed }
    }

    /// Déplace un dossier parmi les épinglés. Refusé hors des épinglés, ou dans lui-même ou l'un de
    /// ses sous-dossiers.
    mutating func moveFolder(_ id: UUID, to destination: SidebarDestination) {
        guard case let .pinned(target, requestedIndex) = destination,
              let source = pinned.location(of: id),
              let folder = pinned.folder(id),
              target != id,
              target.map({ folder.items.folder($0) == nil }) ?? true
        else {
            return
        }
        var index = requestedIndex
        if source.parent == target, source.index < index {
            index -= 1
        }
        guard let item = pinned.removeItem(id) else {
            return
        }
        if !pinned.insert(item, inFolder: target, at: index) {
            pinned.append(item)
        }
    }

    /// Supprime un dossier ; son contenu prend sa place dans le dossier parent.
    mutating func removeFolder(_ id: UUID) {
        guard let location = pinned.location(of: id), case let .folder(folder) = pinned.removeItem(id) else {
            return
        }
        for (offset, child) in folder.items.enumerated() {
            pinned.insert(child, inFolder: location.parent, at: location.index + offset)
        }
    }

    /// Remplace les favoris par `ids`, dans cet ordre (chacun est retiré d'ailleurs).
    mutating func setFavorites(_ ids: [UUID]) {
        favorites = []
        for id in ids {
            remove(id)
            favorites.append(id)
        }
    }

    /// Retire l'onglet, où qu'il soit.
    mutating func remove(_ id: UUID) {
        favorites.removeAll { $0 == id }
        today.removeAll { $0 == id }
        pinned = pinned.removingTab(id)
    }

    /// Liste qui contient directement un onglet.
    private enum Container: Equatable {
        case favorites
        case pinned(folder: UUID?)
        case today

        init(_ destination: SidebarDestination) {
            switch destination {
            case .favorites: self = .favorites
            case let .pinned(folder, _): self = .pinned(folder: folder)
            case .today: self = .today
            }
        }
    }

    private func container(of id: UUID) -> (container: Container, index: Int)? {
        if let index = favorites.firstIndex(of: id) {
            return (.favorites, index)
        }
        if let index = today.firstIndex(of: id) {
            return (.today, index)
        }
        return pinned.location(of: id).map { (.pinned(folder: $0.parent), $0.index) }
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        min(max(index, 0), count)
    }
}
