import Foundation
import WebKit

/// Choice made in the context menu of a page (task 5.9), waiting for the window WebKit is about to open for it.
///
/// No public API gives the link under the pointer: a Matcha item triggers WebKit's “… in New Window” item, which
/// opens the window asynchronously (round trip with the page's process) through `createWebViewWith`. The choice
/// recorded here says what it becomes.
nonisolated struct PageMenuIntent: Equatable, Sendable {
    /// Validity period: WebKit answers within a few milliseconds; beyond that, a window comes from the page.
    static let lifetime: TimeInterval = 1

    let destination: PageMenuDestination
    /// Point from which Peek grows: the pointer when the menu opened, as fractions of the page.
    let openingPoint: CGPoint
    /// Beyond it, the choice is forgotten and the window follows the usual rules.
    let deadline: Date
}

/// What is known about a window the page asks for (`createWebViewWith`).
nonisolated struct PageMenuWindowRequest: Equatable, Sendable {
    /// `.other` for the window of “… in New Window” (checked) as for `window.open`;
    /// `.linkActivated` for a `target=_blank` link, `.formSubmitted` for a form.
    var navigationType: WKNavigationType
    /// True if the page gives a size (sign-in window, task 5.8): never the case for a window from the menu.
    var opensPopupWindow: Bool
}

/// The pending choice of a web view: only one at a time, returned only once, forgotten at the deadline.
nonisolated struct PendingPageMenuIntent: Sendable {
    private(set) var intent: PageMenuIntent?

    /// Records a choice made at `now`; it replaces the previous one.
    mutating func choose(_ destination: PageMenuDestination, openingPoint: CGPoint, at now: Date) {
        intent = PageMenuIntent(
            destination: destination,
            openingPoint: openingPoint,
            deadline: now.addingTimeInterval(PageMenuIntent.lifetime),
        )
    }

    mutating func cancel() {
        intent = nil
    }

    /// The pending choice if the window requested at `now` may come from it; it is then forgotten. An expired choice
    /// is forgotten without being returned. A window that cannot come from the menu (link, form, given size) leaves it
    /// pending: the menu's window may still arrive.
    mutating func take(for request: PageMenuWindowRequest, at now: Date) -> PageMenuIntent? {
        guard let intent else {
            return nil
        }
        guard now <= intent.deadline else {
            self.intent = nil
            return nil
        }
        guard request.navigationType == .other, !request.opensPopupWindow else {
            return nil
        }
        self.intent = nil
        return intent
    }
}
