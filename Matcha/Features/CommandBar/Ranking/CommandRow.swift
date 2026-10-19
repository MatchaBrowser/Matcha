import Foundation

/// Effect of a command bar row.
nonisolated enum CommandTarget: Equatable, Sendable {
    /// Open the address in the target tab, or in a new tab.
    case open(URL)
    case switchToTab(TabReference)
    case perform(CommandActionID)
}

/// Row displayed by the command bar.
nonisolated struct CommandRow: Identifiable, Equatable, Sendable {
    enum Style: Equatable, Sendable {
        /// Open the typed text read as an address, or the unmodified ⌘L address.
        case openAddress
        /// Search the typed text.
        case search
        /// Search a domain name typed alone, as the 2nd row.
        case searchAlternative
        /// `spaceName` is nil for a tab of the displayed Space.
        case tab(TabReference, place: TabPlace, spaceName: String?)
        case history
        case suggestion
        case action(CommandActionID)
    }

    let id: String
    let style: Style
    /// Data displayed as is (address, page title, suggestion); action titles are already localized by their
    /// source.
    let title: String
    /// Address displayed under the title, if there is one. Localized subtitles (“Search %@”) are produced by the
    /// view according to `style`.
    let subtitle: String?
    /// Address opened or shown by the row; nil for actions.
    let url: URL?
    let target: CommandTarget
}
