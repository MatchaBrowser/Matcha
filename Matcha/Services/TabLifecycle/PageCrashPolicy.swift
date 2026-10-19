/// What a page does when its process terminates (task 5.7).
nonisolated enum PageCrashAction: String, Equatable, Sendable {
    /// Visible page: reloaded right away, in the same web view (back/forward history kept).
    case reload
    /// Hidden page: web view released as when the tab is put to sleep (task 5.6), recreated when it is displayed.
    case reloadWhenShown
    /// Repeated terminations: no more automatic reload, a message in the page invites the user to reload it.
    case showProblem
}

/// Rules for recovering a page whose process terminated (crash, or process terminated by the system for memory; task
/// 5.7). “Visible”: selected tab or pane of its split, in the displayed Space of an open window (notion from task 5.6),
/// Peek page, mini window page.
nonisolated enum PageCrashPolicy {
    /// Automatic reloads allowed within a `PageCrashCounter` time window: beyond that, the page waits for the user.
    static let automaticReloads = 1

    /// `recentTerminations`: terminations in the last 30 seconds, this one included (`PageCrashCounter`).
    static func action(isVisible: Bool, recentTerminations: Int) -> PageCrashAction {
        if recentTerminations > automaticReloads {
            return .showProblem
        }
        return isVisible ? .reload : .reloadWhenShown
    }
}
