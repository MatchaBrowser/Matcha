import Foundation

/// What a typed text designates: an address to open or a search to run.
nonisolated enum AddressInterpretation: Equatable, Sendable {
    case address(URL)
    /// Search for the text on the chosen engine; the URL is that of the results page.
    case search(URL)

    var url: URL {
        switch self {
        case let .address(url), let .search(url): url
        }
    }
}
