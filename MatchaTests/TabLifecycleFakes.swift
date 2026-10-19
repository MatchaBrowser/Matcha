import Foundation
@testable import Matcha
import WebKit

/// Simulated WebKit answers for suspension: pages that play sound, requested snapshots.
@MainActor
final class FakeTabProbes {
    var playing: Set<ObjectIdentifier> = []
    /// Questions asked to WebKit about sound (task 5.10: never for a tab whose icon shows it is playing some).
    var mediaRequests = 0
    var snapshotRequests = 0
    /// Called during each snapshot (the user shows the tab in the meantime…).
    var duringSnapshot: (() -> Void)?

    func probes() -> TabLifecycleProbes {
        TabLifecycleProbes(
            isPlayingMedia: { [self] webView in
                mediaRequests += 1
                return playing.contains(ObjectIdentifier(webView))
            },
            snapshot: { [self] _, url in
                snapshotRequests += 1
                duringSnapshot?()
                return TabSnapshot(data: Data([0xFF, 0xD8]), url: url, pageWidth: 800)
            },
        )
    }
}
