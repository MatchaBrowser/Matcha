import Foundation

/// Tab imported from another browser (tasks 7.1 and 7.2): its address and its title. Pure type.
nonisolated struct ImportedTab: Equatable, Sendable {
    var title: String
    var url: URL
}

/// Imported item: a tab, or a folder and its content, in the original order. Pure type.
indirect nonisolated enum ImportNode: Equatable, Sendable {
    case tab(ImportedTab)
    case folder(name: String, children: [ImportNode])

    /// Number of tabs, folders included.
    static func tabCount(of nodes: [ImportNode]) -> Int {
        nodes.reduce(0) { count, node in
            switch node {
            case .tab: count + 1
            case let .folder(_, children): count + tabCount(of: children)
            }
        }
    }

    /// Number of folders, subfolders included.
    static func folderCount(of nodes: [ImportNode]) -> Int {
        nodes.reduce(0) { count, node in
            switch node {
            case .tab: count
            case let .folder(_, children): count + 1 + folderCount(of: children)
            }
        }
    }

    /// Tabs only, folders flattened, in order.
    static func flattenedTabs(of nodes: [ImportNode]) -> [ImportedTab] {
        nodes.flatMap { node -> [ImportedTab] in
            switch node {
            case let .tab(tab): [tab]
            case let .folder(_, children): flattenedTabs(of: children)
            }
        }
    }
}
