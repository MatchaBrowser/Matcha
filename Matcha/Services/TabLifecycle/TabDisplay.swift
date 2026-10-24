import Foundation

/// A browser window, as tab sleeping sees it (task 5.6): the tabs it displays in its displayed Space are visible, and
/// the source tab of the Peek it shows.
@MainActor
protocol TabDisplay: AnyObject {
    var visibleTabIDs: Set<UUID> { get }
}
