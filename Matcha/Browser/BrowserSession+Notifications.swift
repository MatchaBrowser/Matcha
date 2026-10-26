import Foundation

extension BrowserSession {
    /// The notification decision of `origin` changed in the site settings: its open pages of profile `profileID`
    /// follow at once, without waiting for their next document (review IU16): an allowed page no longer goes to sleep,
    /// and its scripts read the new decision (review WB10).
    func notificationDecisionDidChange(_ decision: SitePermissionDecision?, origin: SiteOrigin, profileID: UUID?) {
        for manager in allTabManagers where manager.sitePermissions?.profileID == profileID {
            for tab in manager.tabs where SiteOrigin.web(of: tab.documentURL) == origin {
                tab.canSendNotifications = decision == .allow
                manager.coordinator.notificationDecisionDidChange(decision, origin: origin, on: tab)
            }
        }
    }
}
