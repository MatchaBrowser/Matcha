import Foundation

/// Matcha command in the context menu of a page (right-click outside a link, an image or selected text): back,
/// forward, save as, print, page source.
nonisolated enum PageCommand: String, CaseIterable, Sendable {
    case goBack = "GoBack"
    case goForward = "GoForward"
    case saveAs = "SaveAs"
    case print = "Print"
    case viewSource = "ViewSource"

    /// Identifier of the menu item, modeled on WebKit's.
    var identifier: String {
        "MatchaMenuItemIdentifier" + rawValue
    }
}

/// A line of a rewritten page menu: a WebKit item (by its position in the original menu), a Matcha command, or a
/// separator.
nonisolated enum PageMenuEntry: Equatable, Sendable {
    case webKit(Int)
    case command(PageCommand)
    case separator
}

nonisolated extension PageMenuPlan {
    /// WebKit's “Reload”: it is only in the menu of a page (not of a link, an image or text).
    static let reloadIdentifier = "WKMenuItemIdentifierReload"
    /// WebKit's “Back” and “Forward”, when it adds them: replaced by Matcha's, always present.
    static let historyIdentifiers: Set<String> = ["WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward"]
    /// “Inspect Element” (developer tools): kept last.
    static let inspectIdentifier = "WKMenuItemIdentifierInspectElement"

    /// Menu of a page, as in Chrome: Back, Forward, Reload; Save As…, Print…; the other WebKit items; View Page
    /// Source, then “Inspect Element” if it is there. `identifiers`: those of the items of the original menu, in order
    /// (nil without an identifier); `separators`: the positions of its separators, replaced by Matcha's. nil if this is
    /// not the menu of a page.
    static func pageLayout(for identifiers: [String?], separators: Set<Int>) -> [PageMenuEntry]? {
        guard let reload = identifiers.firstIndex(of: reloadIdentifier) else {
            return nil
        }
        let inspect = identifiers.firstIndex(of: inspectIdentifier)
        let others = identifiers.indices.filter { index in
            index != reload && index != inspect && !separators.contains(index)
                && !(identifiers[index].map(historyIdentifiers.contains) ?? false)
        }
        var entries: [PageMenuEntry] = [.command(.goBack), .command(.goForward), .webKit(reload)]
        entries += [.separator, .command(.saveAs), .command(.print)]
        if !others.isEmpty {
            entries.append(.separator)
            entries += others.map(PageMenuEntry.webKit)
        }
        entries += [.separator, .command(.viewSource)]
        if let inspect {
            entries.append(.webKit(inspect))
        }
        return entries
    }
}
