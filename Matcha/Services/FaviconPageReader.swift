import Foundation
import WebKit

/// Reads a website's icon from inside its page (`fetch` in a separate JavaScript world), with the page's network
/// context: its cookies, the certificate the user accepted, this Mac's local network. An icon behind a sign-in or on
/// a home server is found as the page shows it. An SVG icon is drawn into a bitmap by WebKit, in its sandboxed process:
/// the app's process still only decodes bitmaps (`FaviconDecoder`, audit W8). A cross-origin icon that the website
/// doesn't share is left to the download without cookies (`FaviconService.fetchIcon`).
nonisolated enum FaviconPageReader {
    /// Side of an SVG icon drawn into a bitmap, in pixels.
    static let drawnSide = 128

    /// JavaScript function body: the first of `urls` that loads, as base 64 (an SVG drawn as PNG); null if none does.
    static let script = """
    for (const href of urls) {
        try {
            const response = await fetch(href, { credentials: 'include' });
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
                    canvas.getContext('2d').drawImage(image, 0, 0, side, side);
                    return canvas.toDataURL('image/png').split(',')[1];
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

    /// The first icon of `urls` that the page displayed in `webView` can load; nil if none.
    @MainActor
    static func read(_ urls: [URL], from webView: WKWebView, maximumSize: Int) async -> Data? {
        guard !urls.isEmpty else {
            return nil
        }
        let arguments: [String: Any] = ["urls": urls.map(\.absoluteString), "maximum": maximumSize, "side": drawnSide]
        let result = try? await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: .defaultClient)
        return (result as? String).flatMap { Data(base64Encoded: $0) }
    }
}
