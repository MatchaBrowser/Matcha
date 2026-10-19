import Foundation
import OSLog
import WebKit

/// Find in the tab's page (task 5.3), through WebKit's public API: `find(_:configuration:)` only tells whether a match
/// exists (`WKFindResult.matchFound`), not how many; the match found becomes the page's selection, and the page
/// scrolls to it.
extension BrowserTab: FindPerformer {
    /// Deselects, in a separate JavaScript world that the page cannot modify. Main frame only: a match found in an
    /// embedded frame stays selected.
    static let deselectScript = "window.getSelection().removeAllRanges(); true"

    func search(_ query: String, direction: FindDirection) async -> Bool? {
        guard let webView else {
            return nil
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = direction == .backward
        configuration.caseSensitive = false
        configuration.wraps = true
        do {
            return try await webView.find(query, configuration: configuration).matchFound
        } catch {
            // Never the searched text.
            Logger.browser.error("Find in page failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    func deselectMatch() {
        webView?.evaluateJavaScript(Self.deselectScript, in: nil, in: .defaultClient)
    }
}
