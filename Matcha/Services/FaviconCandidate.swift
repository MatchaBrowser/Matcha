import Foundation
import WebKit

/// Icon declared by a page (`<link rel="icon">`, `apple-touch-icon`…).
nonisolated struct FaviconCandidate: Equatable, Sendable {
    var url: URL
    var rel: String
    /// Value of the `sizes` attribute: “32x32”, “16x16 32x32”, “any”…
    var sizes: String
    /// Declared MIME type: “image/png”, “image/svg+xml”…
    var type: String

    init(url: URL, rel: String, sizes: String = "", type: String = "") {
        self.url = url
        self.rel = rel
        self.sizes = sizes
        self.type = type
    }

    /// Reads an element of the array returned by `extractionScript`.
    init?(dictionary: [String: Any]) {
        guard let href = dictionary["href"] as? String, let url = URL(string: href) else {
            return nil
        }
        self.init(
            url: url,
            rel: dictionary["rel"] as? String ?? "",
            sizes: dictionary["sizes"] as? String ?? "",
            type: dictionary["type"] as? String ?? "",
        )
    }

    /// JavaScript function body that lists the declared icons, with their absolute addresses.
    static let extractionScript = """
    const selector = 'link[rel~="icon" i], link[rel~="apple-touch-icon" i], link[rel~="apple-touch-icon-precomposed" i]';
    return Array.from(document.querySelectorAll(selector)).map(link => ({
        href: link.href,
        rel: link.rel,
        sizes: link.getAttribute('sizes') || '',
        type: link.type || ''
    }));
    """

    /// Icons declared by the page displayed in `webView`. The script runs in a separate JavaScript world, which the
    /// page cannot modify.
    @MainActor
    static func extract(from webView: WKWebView) async -> [FaviconCandidate] {
        let result = try? await webView.callAsyncJavaScript(extractionScript, contentWorld: .defaultClient)
        let links = result as? [[String: Any]] ?? []
        return links.compactMap(FaviconCandidate.init(dictionary:))
    }
}
