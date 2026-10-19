import Foundation
import SwiftData

/// Visit to a page (task 5.5): a main page that loaded, or an address changed by the page itself
/// (`HistoryRecordingPolicy`). Never for a private window. Stays on the Mac (`SYNC.md`), kept for one year.
@Model
final class HistoryRecord {
    var id = UUID()
    /// Address without fragment or credentials (`HistoryRecordingPolicy.storedURL`).
    var url: URL?
    /// Key of the address (`CommandText.urlKey`), computed once on write: visits to the same page are grouped
    /// without re-reading each address when the history loads.
    var urlKey = ""
    var title: String?
    var visitDate = Date.now
    /// The page's profile (no relationship: deleted explicitly with the profile, like `SitePermissionRecord`).
    var profileID: UUID?
    /// Space of the tab or the peek; nil for a mini window.
    var spaceID: UUID?

    init(id: UUID = UUID(), url: URL, urlKey: String, title: String?, visitDate: Date, profileID: UUID?, spaceID: UUID?) {
        self.id = id
        self.url = url
        self.urlKey = urlKey
        self.title = title
        self.visitDate = visitDate
        self.profileID = profileID
        self.spaceID = spaceID
    }
}
