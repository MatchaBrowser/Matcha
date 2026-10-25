import Foundation
import WebKit

/// Observation of the tab's web view (`BrowserTab.observe`).
extension BrowserTab {
    /// Makes a KVO handler that copies the web view's state into the tab.
    /// WebKit sends its KVO notifications on the main thread. A view already replaced is ignored.
    func sync<Value>(
        _ apply: @escaping @MainActor @Sendable (BrowserTab, WKWebView) -> Void,
    ) -> @Sendable (WKWebView, NSKeyValueObservedChange<Value>) -> Void {
        { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, self.webView === webView else {
                    return
                }
                apply(self, webView)
            }
        }
    }
}
