import Foundation
@testable import Matcha
import WebKit

/// Réponses de WebKit simulées pour la mise en veille : pages qui jouent du son, captures demandées.
@MainActor
final class FakeTabProbes {
    var playing: Set<ObjectIdentifier> = []
    var snapshotRequests = 0
    /// Appelé pendant chaque capture (l'utilisateur affiche l'onglet pendant ce temps…).
    var duringSnapshot: (() -> Void)?

    func probes() -> TabLifecycleProbes {
        TabLifecycleProbes(
            isPlayingMedia: { [self] webView in playing.contains(ObjectIdentifier(webView)) },
            snapshot: { [self] _, url in
                snapshotRequests += 1
                duringSnapshot?()
                return TabSnapshot(data: Data([0xFF, 0xD8]), url: url, pageWidth: 800)
            },
        )
    }
}
