import AppKit
import Foundation
import WebKit

/// Keeps the decisions passed to WebKit's `decisionHandler`.
@MainActor
final class PolicyRecorder {
    private(set) var policies: [WKNavigationActionPolicy] = []

    func record(_ policy: WKNavigationActionPolicy) {
        policies.append(policy)
    }
}

/// Click on a link, with the chosen modifiers and button (WebKit mask: 1 left, 2 right, 4 middle, 0 click simulated by
/// the page).
///
/// Every property the coordinator reads must be overridden here: reading a property that is not overridden on a
/// hand-made `WKNavigationAction` crashes the test. `targetFrame` is nil: the fake always looks like a link that opens
/// a new window; `sourceFrame` too: a load started by the app. `navigationType`: `.other` for `window.open` or the window of a context menu
/// item (verified, task
/// 5.9: no button and no key).
@MainActor
final class FakeNavigationAction: WKNavigationAction {
    private let fakeRequest: URLRequest
    private let fakeModifierFlags: NSEvent.ModifierFlags
    private let fakeButtonNumber: Int
    private let fakeShouldPerformDownload: Bool
    private let fakeNavigationType: WKNavigationType

    init(
        url: URL,
        modifierFlags: NSEvent.ModifierFlags,
        buttonNumber: Int = 1,
        shouldPerformDownload: Bool = false,
        navigationType: WKNavigationType = .linkActivated,
    ) {
        fakeRequest = URLRequest(url: url)
        fakeModifierFlags = modifierFlags
        fakeButtonNumber = buttonNumber
        fakeShouldPerformDownload = shouldPerformDownload
        fakeNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest {
        fakeRequest
    }

    override var modifierFlags: NSEvent.ModifierFlags {
        fakeModifierFlags
    }

    override var navigationType: WKNavigationType {
        fakeNavigationType
    }

    override var buttonNumber: Int {
        fakeButtonNumber
    }

    override var targetFrame: WKFrameInfo? {
        nil
    }

    /// No source frame, as WebKit gives for a load started by the app: declared non-null, hence the cast of nil.
    override var sourceFrame: WKFrameInfo {
        unsafeBitCast(WKFrameInfo?.none, to: WKFrameInfo.self)
    }

    override var shouldPerformDownload: Bool {
        fakeShouldPerformDownload
    }
}
