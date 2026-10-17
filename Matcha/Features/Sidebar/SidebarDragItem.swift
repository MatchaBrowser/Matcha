import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Éléments glissés de la barre : type dynamique (aucune déclaration dans l'Info.plist), connu de Matcha seule.
    /// Ni la page (`WKWebView`) ni une autre app ne l'acceptent.
    static let matchaSidebarItem = UTType(mimeType: "application/x-matcha-sidebar-item", conformingTo: .data)!
}

/// Élément glissé dans la barre latérale : un onglet, un split ou un dossier d'épinglés, par son identifiant.
///
/// L'identifiant voyage en texte préfixé, encodé en UTF-8 dans un type de données privé (voir DECISIONS.md) :
/// une page ne reçoit jamais « matcha-tab:… » dans un champ. Toute autre donnée est refusée.
nonisolated enum SidebarDragItem: Transferable, Equatable, Sendable {
    case tab(UUID)
    case folder(UUID)
    case split(UUID)

    private static let tabPrefix = "matcha-tab:"
    private static let folderPrefix = "matcha-folder:"
    private static let splitPrefix = "matcha-split:"

    var text: String {
        switch self {
        case let .tab(id): Self.tabPrefix + id.uuidString
        case let .folder(id): Self.folderPrefix + id.uuidString
        case let .split(id): Self.splitPrefix + id.uuidString
        }
    }

    init?(text: String) {
        if let id = Self.id(in: text, after: Self.tabPrefix) {
            self = .tab(id)
        } else if let id = Self.id(in: text, after: Self.folderPrefix) {
            self = .folder(id)
        } else if let id = Self.id(in: text, after: Self.splitPrefix) {
            self = .split(id)
        } else {
            return nil
        }
    }

    /// Texte UTF-8 de `text`.
    init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        self.init(text: text)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .matchaSidebarItem) { item in
            Data(item.text.utf8)
        } importing: { data in
            guard let item = SidebarDragItem(data: data) else {
                throw NotASidebarItemError()
            }
            return item
        }
    }

    struct NotASidebarItemError: Error {}

    private static func id(in text: String, after prefix: String) -> UUID? {
        text.hasPrefix(prefix) ? UUID(uuidString: String(text.dropFirst(prefix.count))) : nil
    }
}
