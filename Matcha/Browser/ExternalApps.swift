import CoreGraphics
import Foundation

/// An app that handles a kind of link (`mailto:`, `zoommtg:`…), as the page's banner names it.
struct ExternalApp {
    /// Its name (“Zoom”); nil if the system does not give it.
    let name: String?
    /// Its icon; nil: the banner shows the action's symbol.
    let icon: CGImage?
}

/// Links to other apps (audit W2): the system's (`ExternalApps.system`, one per platform: `ExternalApps+AppKit`),
/// replaced in tests.
@MainActor
struct ExternalApps {
    /// Hands `url` to the app that handles it; false if none does.
    var open: (URL) -> Bool
    /// App that handles `url`; nil if none does.
    var handler: (URL) -> ExternalApp?
}
