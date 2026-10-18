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
    /// Splits du Space : 2 à 4 onglets voisins d'un même conteneur (voir SidebarLayout+Splits), triés par
    /// identifiant. Changés seulement par `setSplits` ; `normalizeSplits` rétablit leurs règles après chaque changement.
    private(set) var splits: [SplitGroup] = []

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

    /// Place l'onglet parmi ceux du jour, à `index` (borné), en le retirant d'ailleurs (et de son split).
    mutating func insertToday(_ id: UUID, at index: Int) {
        detachFromSplit(id)
        takeOut(id)
        today.insert(id, at: Self.clamp(index, count: today.count))
        normalizeSplits()
    }

    /// Change la place de l'onglet : en fin de favoris ou d'épinglés, ou en tête des onglets du jour.
    /// Sans effet s'il y est déjà.
    mutating func setPlace(_ id: UUID, to place: TabPlace) {
        guard self.place(of: id) != place else {
            return
        }
        detachFromSplit(id)
        takeOut(id)
        switch place {
        case .favorite: favorites.append(id)
        case .pinned: pinned.append(.tab(id))
        case .today: today.insert(id, at: 0)
        }
        normalizeSplits()
    }

    /// Déplace un onglet déjà rangé vers `destination` (glisser-déposer) ; il quitte son split. Un dossier
    /// inconnu renvoie l'onglet à la fin des épinglés.
    mutating func move(_ id: UUID, to destination: SidebarDestination) {
        guard place(of: id) != nil else {
            return
        }
        detachFromSplit(id)
        placeTab(id, at: destination)
        normalizeSplits()
    }

    /// Primitive sans règle de split : déplace l'onglet rangé `id` à `destination` (rang lu avant le déplacement).
    mutating func placeTab(_ id: UUID, at destination: SidebarDestination) {
        var index = destination.index
        // Dans le même conteneur, retirer l'onglet décale d'un cran les rangs qui le suivent.
        if let source = container(of: id), source.container == Container(destination), source.index < index {
            index -= 1
        }
        takeOut(id)
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

    /// Primitive : place `id` juste après `previous`, dans le conteneur de `previous` ; sans effet s'il y est déjà.
    mutating func placeTab(_ id: UUID, after previous: UUID) {
        guard id != previous, let anchor = container(of: previous) else {
            return
        }
        if let current = container(of: id), current.container == anchor.container, current.index == anchor.index + 1 {
            return
        }
        placeTab(id, at: anchor.container.destination(at: anchor.index + 1))
    }

    /// Remplace les splits, puis rétablit leurs règles.
    mutating func setSplits(_ groups: [SplitGroup]) {
        splits = groups
        normalizeSplits()
    }

    /// Crée un dossier d'épinglés vide dans `parent` (nil : la racine), à `index` ou à la fin.
    @discardableResult
    mutating func addFolder(id: UUID = UUID(), named name: String, in parent: UUID? = nil, at index: Int? = nil) -> UUID {
        let folder = PinnedFolder(id: id, name: name)
        if !pinned.insert(.folder(folder), inFolder: parent, at: index ?? Int.max) {
            pinned.append(.folder(folder))
        }
        normalizeSplits()
        return folder.id
    }

    mutating func renameFolder(_ id: UUID, to name: String) {
        pinned.updateFolder(id) { $0.name = name }
    }

    mutating func setFolderCollapsed(_ id: UUID, _ isCollapsed: Bool) {
        pinned.updateFolder(id) { $0.isCollapsed = isCollapsed }
    }

    mutating func setFolderAppearance(_ id: UUID, _ appearance: FolderAppearance) {
        pinned.updateFolder(id) { $0.appearance = appearance }
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
        normalizeSplits()
    }

    /// Supprime un dossier ; son contenu prend sa place dans le dossier parent.
    mutating func removeFolder(_ id: UUID) {
        guard let location = pinned.location(of: id), case let .folder(folder) = pinned.removeItem(id) else {
            return
        }
        for (offset, child) in folder.items.enumerated() {
            pinned.insert(child, inFolder: location.parent, at: location.index + offset)
        }
        normalizeSplits()
    }

    /// Remplace les favoris par `ids`, dans cet ordre (chacun est retiré d'ailleurs).
    mutating func setFavorites(_ ids: [UUID]) {
        favorites = []
        for id in ids {
            takeOut(id)
            favorites.append(id)
        }
        normalizeSplits()
    }

    /// Retire l'onglet, où qu'il soit (et de son split).
    mutating func remove(_ id: UUID) {
        takeOut(id)
        normalizeSplits()
    }

    /// Liste qui contient directement un onglet.
    enum Container: Equatable {
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

        /// Destination « au rang `index` » de cette liste.
        func destination(at index: Int) -> SidebarDestination {
            switch self {
            case .favorites: .favorites(index: index)
            case let .pinned(folder): .pinned(folder: folder, index: index)
            case .today: .today(index: index)
            }
        }
    }

    /// Liste qui contient directement l'onglet, et son rang dans celle-ci.
    func container(of id: UUID) -> (container: Container, index: Int)? {
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

    /// Ancien corps de `remove` : retire l'onglet des favoris, des onglets du jour et des épinglés.
    private mutating func takeOut(_ id: UUID) {
        favorites.removeAll { $0 == id }
        today.removeAll { $0 == id }
        pinned = pinned.removingTab(id)
    }

    /// Retire l'onglet du split qui le contient (le split est défait par `normalizeSplits` sous deux onglets).
    private mutating func detachFromSplit(_ id: UUID) {
        if let index = splits.firstIndex(where: { $0.contains(id) }) {
            splits[index].remove(id)
        }
    }

    /// Rétablit les règles des splits : membres rangés hors des favoris, dans un seul conteneur (celui du
    /// premier), 4 au plus, regroupés dans l'ordre de la barre ; un onglet dans un seul split ; 2 membres au
    /// moins. Une passe suffit : un groupe regroupé ne contient que ses membres, les suivants n'y entrent pas.
    private mutating func normalizeSplits() {
        guard !splits.isEmpty else {
            return
        }
        let rank = Dictionary(orderedTabIDs.enumerated().map { ($1, $0) }) { first, _ in first }
        var claimed: Set<UUID> = []
        var kept: [SplitGroup] = []
        for var group in splits {
            let present = group.tabIDs
                .filter { rank[$0] != nil && place(of: $0) != .favorite && !claimed.contains($0) }
                .sorted { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
            guard let first = present.first, let home = container(of: first)?.container else {
                continue
            }
            let members = Array(present.filter { container(of: $0)?.container == home }.prefix(SplitGroup.paneCount.upperBound))
            guard members.count >= SplitGroup.paneCount.lowerBound else {
                continue
            }
            for (previous, id) in zip(members, members.dropFirst()) {
                placeTab(id, after: previous)
            }
            group.setMembers(members)
            claimed.formUnion(members)
            kept.append(group)
        }
        kept.sort { $0.id.uuidString < $1.id.uuidString }
        if kept != splits {
            splits = kept
        }
    }
}
