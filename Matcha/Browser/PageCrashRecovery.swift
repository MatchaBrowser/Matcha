import Foundation
import Observation

/// Recovery of a page (tab, Peek, mini window) whose process stopped (task 5.7, `NavigationCoordinator+Crash`).
/// WebKit clears the address and title of the web view right after notifying the delegate: from the termination until
/// the end of the next load, the tab keeps its own (`isRecovering`). After repeated terminations, the page shows a
/// message and no longer reloads by itself (`isShowingProblem`).
@MainActor
@Observable
final class PageCrashRecovery {
    /// Followed page: read again at the end of the reload.
    @ObservationIgnored weak var page: BrowserTab?
    /// “This page had a problem” message displayed over the page, until it is reloaded.
    private(set) var isShowingProblem = false
    /// True from the process termination until the end of the next load (finished or failed) or the view's release.
    @ObservationIgnored private(set) var isRecovering = false
    @ObservationIgnored private var counter = PageCrashCounter()

    /// The page's process has just stopped, at `date`: returns the number of recent terminations, this one included.
    func processDidTerminate(at date: Date) -> Int {
        isRecovering = true
        return counter.record(at: date)
    }

    /// Repeated terminations: the page waits for the user to reload it.
    func showProblem() {
        if !isShowingProblem {
            isShowingProblem = true
        }
    }

    /// Reload or other navigation requested: the message goes away right away; the tab's address and title stay
    /// protected until the end of the load.
    func pageWillNavigate() {
        if isShowingProblem {
            isShowingProblem = false
        }
    }

    /// Load finished or failed, web view released: the tab follows its web view again. Recent terminations stay
    /// counted.
    func end() {
        pageWillNavigate()
        guard isRecovering else {
            return
        }
        isRecovering = false
        page?.syncWithWebView()
    }
}
