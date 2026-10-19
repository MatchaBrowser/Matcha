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
            Logger.browser.notice("État de navigation illisible : l'onglet sera restauré depuis son adresse")
            return false
        }
        savedInteractionState = state
        return true
    }
}
