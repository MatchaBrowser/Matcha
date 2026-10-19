import AppKit
import WebKit

/// What tab sleeping asks WebKit (task 5.6), replaceable in the tests: the sound, and the page snapshot. Both are
/// asynchronous; without an answer in time, the page is considered busy (no sleep) or without a snapshot.
@MainActor
struct TabLifecycleProbes {
    /// WebKit's answer deadline: a page that does not answer may be playing sound.
    static let timeout = Duration.seconds(2)

    /// True if the page is playing media, or if WebKit did not answer in time.
    var isPlayingMedia: @MainActor (WKWebView) async -> Bool
    /// Snapshot of the page displayed by the view (its address is given separately), or nil.
    var snapshot: @MainActor (WKWebView, URL?) async -> TabSnapshot?

    static let webKit = TabLifecycleProbes(isPlayingMedia: isPlayingMedia(in:), snapshot: snapshot(of:url:))

    /// `requestMediaPlaybackState`: only “playing” counts (a paused video can be unloaded). Conservative: as
    /// checked (task 5.10), WebKit answers “playing” as soon as a media element of the page is not paused, even
    /// loaded but never started, or muted (Web Audio and `new Audio()` included), and “paused” when none plays but
    /// one is paused.
    static func isPlayingMedia(in webView: WKWebView) async -> Bool {
        await CallbackTimeout.value(timeout: timeout, fallback: true) { done in
            webView.requestMediaPlaybackState { state in
                done(state == .playing)
            }
        }
    }

    /// `takeSnapshot` of the visible part of the page, without waiting for a screen update: the view of a hidden tab is
    /// in no window (WebKit draws the page anyway). Nothing for a view without a size (tab opened in the background,
    /// never displayed).
    static func snapshot(of webView: WKWebView, url: URL?) async -> TabSnapshot? {
        let width = webView.bounds.width
        guard width >= 1, webView.bounds.height >= 1 else {
            return nil
        }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        let data = await CallbackTimeout.value(timeout: timeout, fallback: nil as Data?) { done in
            webView.takeSnapshot(with: configuration) { image, _ in
                done(image?.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap { TabSnapshot.jpegData(from: $0) })
            }
        }
        return data.map { TabSnapshot(data: $0, url: url, pageWidth: width) }
    }
}
