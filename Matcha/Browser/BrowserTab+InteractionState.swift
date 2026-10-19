import Foundation
import OSLog
import WebKit

extension BrowserTab {
    /// Keeps the web view's navigation state, to restore it later; false if it could not be read.
    @discardableResult
    func captureInteractionState() -> Bool {
        guard let webView else {
            return false
        }
        guard let state = webView.interactionState as? Data else {
            Logger.browser.notice("Unreadable navigation state: the tab will be restored from its address")
            return false
        }
        savedInteractionState = state
        return true
    }
}
