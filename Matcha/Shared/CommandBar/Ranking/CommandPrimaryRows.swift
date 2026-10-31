import Foundation

/// First rows of the bar, computed without waiting for the sources: the typed text, opened as an address or searched
/// as is, and for a bare domain name, its search as the 2nd row.
nonisolated enum CommandPrimaryRows {
    static let id = "primary"
    static let searchAlternativeID = "primary.search"

    /// Row of the unmodified ⌘L address: the whole URL, never reinterpreted.
    static func current(_ url: URL) -> CommandRow {
        CommandRow(id: id, style: .openAddress, title: url.absoluteString, subtitle: nil, url: url, target: .open(url))
    }

    /// No rows for an empty text.
    static func make(for query: CommandQuery) -> [CommandRow] {
        switch query.interpretation {
        case nil:
            return []
        case let .search(url):
            return [CommandRow(id: id, style: .search, title: query.trimmed, subtitle: nil, url: url, target: .open(url))]
        case let .address(url):
            // The subtitle shows the added scheme (https:// or http://).
            let subtitle = url.absoluteString == query.trimmed ? nil : url.absoluteString
            let open = CommandRow(id: id, style: .openAddress, title: query.trimmed, subtitle: subtitle, url: url, target: .open(url))
            guard query.isBareDomain, let searchURL = query.searchEngine.searchURL(for: query.trimmed) else {
                return [open]
            }
            let search = CommandRow(
                id: searchAlternativeID, style: .searchAlternative, title: query.trimmed, subtitle: nil, url: searchURL,
                target: .open(searchURL),
            )
            return [open, search]
        }
    }
}
