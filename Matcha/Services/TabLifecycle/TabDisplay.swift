/// A browser window, as tab sleeping sees it (task 5.6): the tabs displayed by its displayed Space are visible.
@MainActor
protocol TabDisplay: AnyObject {
    var displayedTabManager: TabManager { get }
}
