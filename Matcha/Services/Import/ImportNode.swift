import Foundation

/// Onglet importé d'un autre navigateur (tâches 7.1 et 7.2) : son adresse et son titre. Type pur.
nonisolated struct ImportedTab: Equatable, Sendable {
    var title: String
    var url: URL
}

/// Élément importé : un onglet, ou un dossier et son contenu, dans l'ordre d'origine. Type pur.
indirect nonisolated enum ImportNode: Equatable, Sendable {
    case tab(ImportedTab)
    case folder(name: String, children: [ImportNode])

    /// Nombre d'onglets, dossiers compris.
    static func tabCount(of nodes: [ImportNode]) -> Int {
        nodes.reduce(0) { count, node in
            switch node {
            case .tab: count + 1
            case let .folder(_, children): count + tabCount(of: children)
            }
        }
    }

    /// Nombre de dossiers, sous-dossiers compris.
    static func folderCount(of nodes: [ImportNode]) -> Int {
        nodes.reduce(0) { count, node in
            switch node {
            case .tab: count
            case let .folder(_, children): count + 1 + folderCount(of: children)
            }
        }
    }

    /// Onglets seuls, dossiers mis à plat, dans l'ordre.
    static func flattenedTabs(of nodes: [ImportNode]) -> [ImportedTab] {
        nodes.flatMap { node -> [ImportedTab] in
            switch node {
            case let .tab(tab): [tab]
            case let .folder(_, children): flattenedTabs(of: children)
            }
        }
    }
}
