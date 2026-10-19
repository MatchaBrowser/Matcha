import AppKit

/// A website's request waiting in its page's banner until the user answers (audits W2 and W7).
struct SiteActionRequest: Identifiable {
    let id = UUID()
    let action: SiteAction
    /// Origin of the page; nil if the answer can't be remembered (page without a website: local file).
    let origin: SiteOrigin?
    /// Where to remember “Always”; nil: nowhere.
    let scope: SitePermissionScope?
    /// For a link to another app: its name (“Zoom”) and icon.
    var appName: String?
    var appIcon: NSImage?
    /// Does what the website asked.
    let perform: @MainActor () -> Void
    /// The user said no, or the page went away without an answer.
    var decline: @MainActor () -> Void = {}

    /// “Always” is offered only if the answer can be remembered.
    var canRemember: Bool {
        origin != nil && scope != nil
    }
}
