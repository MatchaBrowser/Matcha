import AppKit
import WebKit

/// Window of a view on this platform (`PopupOpener`).
typealias PlatformWindow = NSWindow

extension WKWebView {
    /// `takeSnapshot`, whose image is an `NSImage` on the Mac (a `UIImage` on iOS): `completion` gets its bitmap, or
    /// nil.
    func takeSnapshotImage(with configuration: WKSnapshotConfiguration, completion: @escaping @MainActor (CGImage?) -> Void) {
        takeSnapshot(with: configuration) { image, _ in
            completion(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }
}
