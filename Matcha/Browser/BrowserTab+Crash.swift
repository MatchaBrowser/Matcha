import Foundation

/// Termination of the page's process (task 5.7): what the tab does about it, per the decision of `PageCrashPolicy`.
extension BrowserTab {
    /// Waking from sleep (task 5.6), recovering after the process terminated (5.7), or a new web view before its first
    /// document (restored or unloaded tab, review WB19): an empty title or a missing address in the web view does not
    /// replace the tab's.
    var keepsTitleAndAddress: Bool {
        suspension.isRestoring || crash.isRecovering || awaitsFirstDocument
    }

    /// Called while WebKit notifies the delegate: the web view still has its address, title and navigation state.
    /// Pending permission requests are denied, find in page and the translation are forgotten and the sound icon is
    /// turned off (there is no page anymore); zoom, icon, title and address remain.
    func webContentProcessDidTerminate(_ action: PageCrashAction) {
        permissionPrompts.denyAll()
        find.pageDidTerminate()
        endPageActivity()
        switch action {
        case .reload:
            // On the next turn of the main loop: WebKit first finishes handling the termination (it clears the view's
            // address and title). Verified: `reload()` starts a new process and reloads the current page of the same
            // web view, back/forward history and zoom included.
            let terminated = webView
            Task { [weak self] in
                guard let self, let terminated, webView === terminated, crash.isRecovering else {
                    return
                }
                reload()
            }
        case .reloadWhenShown:
            // Like putting to sleep (task 5.6), without a snapshot: the navigation state can still be read, the dead
            // view is released and the page comes back, with its history, when the tab is shown.
            suspend(snapshot: nil)
        case .showProblem:
            crash.showProblem()
        }
    }
}
