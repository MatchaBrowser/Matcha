import CoreTransferable
import Foundation

/// Élément glissé dans la barre latérale : un onglet ou un dossier d'épinglés, par son identifiant.
///
/// L'identifiant voyage en texte préfixé : un type propre à l'app serait refusé au dépôt tant qu'il
/// n'est pas déclaré dans l'Info.plist (voir DECISIONS.md). Tout autre texte est refusé.
nonisolated enum SidebarDragItem: Transferable, Equatable, Sendable {
    case tab(UUID)
    case folder(UUID)

    private static let tabPrefix = "matcha-tab:"
    private static let folderPrefix = "matcha-folder:"

    var text: String {
        switch self {
        case let .tab(id): Self.tabPrefix + id.uuidString
        case let .folder(id): Self.folderPrefix + id.uuidString
        }
    }

    init?(text: String) {
        if text.hasPrefix(Self.tabPrefix), let id = UUID(uuidString: String(text.dropFirst(Self.tabPrefix.count))) {
            self = .tab(id)
        } else if text.hasPrefix(Self.folderPrefix), let id = UUID(uuidString: String(text.dropFirst(Self.folderPrefix.count))) {
            self = .folder(id)
        } else {
            return nil
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text) { text in
            guard let item = SidebarDragItem(text: text) else {
                throw NotASidebarItemError()
            }
            return item
        }
    }

    struct NotASidebarItemError: Error {}
}
