import Foundation

/// A browser window, as tab sleeping sees it (task 5.6).
extension WindowModel: TabDisplay {
    var displayedTabManager: TabManager {
        space.tabManager
    }
}
