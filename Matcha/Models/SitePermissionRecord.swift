import Foundation
import SwiftData

/// A profile's remembered decision for a website and a permission (task 5.2): “Always Allow” or “Don't Allow” in
/// the banner, or the choice made in the site settings. “Allow Once” is never saved, nor is a private window
/// (its decisions stay in memory, `SitePermissionStore`). Stays on the Mac (`SYNC.md`).
@Model
final class SitePermissionRecord {
    var id = UUID()
    /// Profile whose pages are concerned.
    var profileID: UUID?
    /// Origin of the main page (`SiteOrigin.key`): “https://meet.google.com”, “http://localhost:8080”.
    var originKey = ""
    /// Permission, as text (`SitePermissionKind`): `camera`, `microphone`.
    var kindValue = ""
    /// Decision, as text (`SitePermissionDecision`): `allow`, `deny`.
    var decisionValue = ""
    var date = Date.now

    init(profileID: UUID?, originKey: String, kind: SitePermissionKind, decision: SitePermissionDecision, date: Date = .now) {
        self.profileID = profileID
        self.originKey = originKey
        kindValue = kind.rawValue
        decisionValue = decision.rawValue
        self.date = date
    }
}
