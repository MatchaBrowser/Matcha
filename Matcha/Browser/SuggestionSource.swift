import Foundation

/// Who suggests searches in the command bar (review A7): the chosen search engine, or another one; the search itself
/// stays with the search engine. Google's suggestions come from Firefox's address (`client=firefox`, Google publishes
/// none): choosing DuckDuckGo or Bing for them avoids it without changing the search engine. Pure type.
nonisolated enum SuggestionSource: String, CaseIterable, Sendable {
    case searchEngine
    case google
    case duckDuckGo
    case bing

    /// Nothing changes until the user chooses: the search engine suggests.
    static let defaultSource = SuggestionSource.searchEngine

    /// Engine asked for suggestions when `searchEngine` searches.
    func engine(for searchEngine: SearchEngine) -> SearchEngine {
        switch self {
        case .searchEngine: searchEngine
        case .google: .google
        case .duckDuckGo: .duckDuckGo
        case .bing: .bing
        }
    }
}
