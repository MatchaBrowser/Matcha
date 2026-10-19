import Foundation
import Observation
import OSLog

/// Permission request waiting for the user's answer in the banner of the page that made it.
struct SitePermissionRequest: Identifiable {
    let id = UUID()
    /// Origin of the main page; nil if it cannot be remembered (page without a host: local file…).
    let origin: SiteOrigin?
    /// Website of the requesting frame, if it is not the page's (embedded frame).
    let frameName: String?
    /// Permissions requested by the page.
    let requested: Set<SitePermissionKind>
    /// Those that the banner asks for: without a remembered decision.
    let asked: Set<SitePermissionKind>
    /// Where to remember the answer; nil: nowhere.
    let scope: SitePermissionScope?
    let response: PermissionResponse

    /// “Always Allow” is offered only if the decision can be remembered.
    var canRemember: Bool {
        origin != nil && scope != nil
    }
}
