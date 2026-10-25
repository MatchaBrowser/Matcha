import Foundation

/// What a row needs for its icon.
@MainActor
struct CommandRowIcons {
    let faviconService: FaviconService
    /// Live tab of a tab row; nil if it no longer exists (or if the bar does not offer tabs).
    let tab: (TabReference) -> BrowserTab?
}
