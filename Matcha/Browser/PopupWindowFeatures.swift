import Foundation
import WebKit

/// Size requested by a page for the window it opens (`window.open(url, name, "width=500,height=600")`, task 5.8),
/// in points, for the page itself (without title bar). A missing, zero, negative or non-finite value does not
/// count: WebKit then uses the default size. The requested position (`left`, `top`) is not kept: `DECISIONS.md`.
nonisolated struct PopupWindowFeatures: Equatable, Sendable {
    let width: Double?
    let height: Double?

    init(width: Double? = nil, height: Double? = nil) {
        self.width = Self.dimension(width)
        self.height = Self.dimension(height)
    }

    /// True if the page gives a size: sign-in window (Google, Apple, bank, payment) in its own window. Otherwise
    /// (`target=_blank` link, `window.open` without size), a tab, as before.
    var opensPopupWindow: Bool {
        width != nil || height != nil
    }

    private static func dimension(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }
}

@MainActor
extension PopupWindowFeatures {
    /// What WebKit passes on from the `window.open` string (verified: each value is given only if the page writes it).
    init(_ features: WKWindowFeatures) {
        self.init(width: features.width?.doubleValue, height: features.height?.doubleValue)
    }
}
