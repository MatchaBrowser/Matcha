import Foundation

/// Ligne de la barre : un onglet, un split (une seule ligne pour tous ses onglets) ou un dossier.
/// `index` : rang de l'onglet, du premier membre ou du dossier dans son conteneur (dépôt « avant la ligne »).
nonisolated enum SidebarRow: Equatable, Sendable, Identifiable {
    case tab(UUID, index: Int)
    case split(SplitGroup, index: Int)
    case folder(PinnedFolder, index: Int)

    /// Onglet, groupe ou dossier.
    var id: UUID {
        switch self {
        case let .tab(id, _): id
        case let .split(group, _): group.id
        case let .folder(folder, _): folder.id
        }
    }

    var index: Int {
        switch self {
        case let .tab(_, index), let .split(_, index), let .folder(_, index): index
        }
    }
}

/// Lignes affichées par la barre : un membre de split donne la ligne de son split s'il en est le premier,
/// et rien sinon.
nonisolated extension SidebarLayout {
    var todayRows: [SidebarRow] {
        today.enumerated().compactMap { index, id in row(forTab: id, index: index) }
    }

    /// Lignes d'un niveau des épinglés (`items` : la racine ou le contenu d'un dossier).
    func pinnedRows(_ items: [PinnedItem]) -> [SidebarRow] {
        items.enumerated().compactMap { index, item in
            switch item {
            case let .tab(id): row(forTab: id, index: index)
            case let .folder(folder): .folder(folder, index: index)
            }
        }
    }

    private func row(forTab id: UUID, index: Int) -> SidebarRow? {
        guard let group = split(containing: id) else {
            return .tab(id, index: index)
        }
        return group.tabIDs.first == id ? .split(group, index: index) : nil
    }
}
