import Foundation
import WebKit

/// Reads a website's icon from inside its page (`fetch` in a separate JavaScript world), with the page's network
/// context: its cookies, the certificate the user accepted, this Mac's local network. An icon behind a sign-in or on
/// a home server is found as the page shows it. An SVG icon is drawn into a bitmap by WebKit, in its sandboxed process:
/// the app's process still only decodes bitmaps (`FaviconDecoder`, audit W8). A cross-origin icon that the website
/// doesn't share is left to the download without cookies (`FaviconService.fetchIcon`). An icon that doesn't answer
/// stops after `requestTimeout`, the whole reading after `timeout` (review SV2).
nonisolated enum FaviconPageReader {
    /// Side of an SVG icon drawn into a bitmap, in pixels.
    static let drawnSide = 128
    /// Longest wait for one icon, in milliseconds.
    static let requestTimeout = 5000
    /// Longest wait for the whole reading.
    static let timeout = Duration.seconds(15)

    /// JavaScript function body: the first of `urls` that loads, as base 64 (an SVG drawn as PNG); null if none does.
    static let script = """
    for (const href of urls) {
        try {
            const response = await fetch(href, { credentials: 'include', signal: AbortSignal.timeout(requestTimeout) });
            if (!response.ok) {
                continue;
            }
            const blob = await response.blob();
            if (blob.size === 0 || blob.size > maximum) {
                continue;
            }
            const path = new URL(href, document.baseURI).pathname.toLowerCase();
            if (blob.type.includes('svg') || path.endsWith('.svg')) {
                const objectURL = URL.createObjectURL(blob);
                try {
                    const image = new Image();
                    image.src = objectURL;
                    await image.decode();
                    const canvas = document.createElement('canvas');
                    canvas.width = side;
                    canvas.height = side;
                    // Drawn in memory, without the GPU: its pixels are read back at once, and a Mac without GPU
                    // rendering (a virtual machine) still gets them.
                    canvas.getContext('2d', { willReadFrequently: true }).drawImage(image, 0, 0, side, side);
                    // A canvas that got no pixels gives “data:,”: no icon, the next one is tried.
                    const png = canvas.toDataURL('image/png');
                    const prefix = 'data:image/png;base64,';
                    if (!png.startsWith(prefix) || png.length === prefix.length) {
                        continue;
                    }
                    return png.slice(prefix.length);
                } finally {
                    URL.revokeObjectURL(objectURL);
                }
            }
            const bytes = new Uint8Array(await blob.arrayBuffer());
            let binary = '';
            for (let index = 0; index < bytes.length; index += 32768) {
                binary += String.fromCharCode.apply(null, bytes.subarray(index, index + 32768));
            }
            return btoa(binary);
        } catch (error) {
            continue;
        }
    }
    return null;
    """

    /// The first icon of `urls` that the page displayed in `webView` can load; nil if none, or after `timeout` (a page
    /// process that never answers).
    @MainActor
    static func read(_ urls: [URL], from webView: WKWebView, maximumSize: Int) async -> Data? {
        guard !urls.isEmpty else {
            return nil
        }
        let arguments: [String: Any] = [
            "urls": urls.map(\.absoluteString),
            "maximum": maximumSize,
            "side": drawnSide,
            "requestTimeout": requestTimeout,
        ]
        let result = await CallbackTimeout.value(timeout: timeout, fallback: nil as String?) { done in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { result in
                done(try? result.get() as? String)
            }
        }
        // An empty answer is no icon either.
        return result.flatMap { Data(base64Encoded: $0) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
