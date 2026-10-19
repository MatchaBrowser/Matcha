import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Items dragged from the sidebar: dynamic type (no declaration in the Info.plist), known only to Matcha.
    /// Neither the page (`WKWebView`) nor another app accepts it.
    static let matchaSidebarItem = UTType(mimeType: "application/x-matcha-sidebar-item", conformingTo: .data)!
}

/// Item dragged in the sidebar: a tab, a split or a pinned folder, by its identifier.
///
/// The identifier travels as prefixed text, encoded in UTF-8 in a private data type (see DECISIONS.md):
/// a page never receives “matcha-tab:…” in a field. Any other data is refused.
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

    /// UTF-8 text of `text`.
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
