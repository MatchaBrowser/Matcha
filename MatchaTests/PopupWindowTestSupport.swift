import Foundation
@testable import Matcha
import WebKit

/// Size requested by a page (`window.open(url, name, "width=…,height=…")`), as WebKit passes it to the delegate.
/// Only the properties the app reads are overridden.
@MainActor
final class FakeWindowFeatures: WKWindowFeatures {
    private let fakeWidth: NSNumber?
    private let fakeHeight: NSNumber?

    init(width: Double? = nil, height: Double? = nil) {
        fakeWidth = width.map { NSNumber(value: $0) }
        fakeHeight = height.map { NSNumber(value: $0) }
        super.init()
    }

    override var width: NSNumber? {
        fakeWidth
    }

    override var height: NSNumber? {
        fakeHeight
    }
}

extension PopupWindowManager {
    /// Usable area of the test screen.
    static let testScreen = CGRect(x: 0, y: 25, width: 1440, height: 875)

    /// Test manager: nothing remembered, no window on screen.
    static func forTests(isPrivate: Bool = false) -> PopupWindowManager {
        let manager = PopupWindowManager(
            faviconService: FaviconService(directory: nil),
            downloadScope: .regular,
            siteZooms: nil,
            isPrivate: isPrivate,
        )
        manager.prepareForTests()
        return manager
    }

    /// No window on screen, and always the same screen.
    func prepareForTests() {
        present = { _ in }
        visibleScreenFrame = { _ in Self.testScreen }
    }
}

extension WKWebView {
    /// `window.open(url, '_blank', features)` in the page; counted as a user gesture by WebKit.
    func openWindow(_ url: URL, features: String) async throws {
        _ = try await evaluateJavaScript("window.open('\(url.absoluteString)', '_blank', '\(features)'); true")
    }

    /// True if the page still has the page that opened it (`window.opener`).
    func hasOpener() async throws -> Bool {
        try await evaluateJavaScript("window.opener !== null") as? Bool == true
    }
}
