import Foundation

/// Address shown for a page (audit W4): that of the displayed document, never one a page is only starting to load.
/// `WKWebView.url` takes the address of a load as soon as it starts: a page could keep its own content on screen
/// under the address of another site, for as long as that site takes to answer. A load the user asked for (address
/// bar, favorite, link opened by the app) shows its address at once, until its document is displayed or it fails.
/// Pure type.
nonisolated struct DisplayedAddress: Equatable, Sendable {
    /// Address of the displayed document.
    private(set) var committed: URL?
    /// Load asked for by the user whose document isn't displayed yet.
    private(set) var requested: URL?

    var url: URL? {
        requested ?? committed
    }

    /// True while a load asked for by the user isn't displayed yet: the shown address isn't the displayed page's.
    var isPending: Bool {
        requested != nil
    }

    /// The tab shows `url` without a web view (restored, unloaded), or is realigned with its web view.
    mutating func reset(to url: URL?) {
        committed = url
        requested = nil
    }

    mutating func userDidRequest(_ url: URL) {
        requested = url
    }

    /// The web view's address changed. Taken only when nothing is loading: a change within the page (`pushState`, an
    /// anchor). During a load, it can be the address of a document that isn't displayed yet.
    mutating func webViewURLDidChange(to url: URL?, isLoading: Bool) {
        if !isLoading {
            committed = url
        }
    }

    /// A new document is displayed (`didCommit`), or the load ended (`didFinish`, `didFail…`): the web view's address
    /// is the displayed document's again.
    mutating func documentDidChange(to url: URL?) {
        committed = url
        requested = nil
    }
}
