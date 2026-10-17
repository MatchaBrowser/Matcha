import Foundation
import WebKit

/// Icône déclarée par une page (`<link rel="icon">`, `apple-touch-icon`…).
nonisolated struct FaviconCandidate: Equatable, Sendable {
    var url: URL
    var rel: String
    /// Valeur de l'attribut `sizes` : « 32x32 », « 16x16 32x32 », « any »…
    var sizes: String
    /// Type MIME déclaré : « image/png », « image/svg+xml »…
    var type: String

    init(url: URL, rel: String, sizes: String = "", type: String = "") {
        self.url = url
        self.rel = rel
        self.sizes = sizes
        self.type = type
    }

    /// Lit un élément du tableau renvoyé par `extractionScript`.
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

    /// Corps de fonction JavaScript qui liste les icônes déclarées, avec leurs adresses absolues.
    static let extractionScript = """
    const selector = 'link[rel~="icon" i], link[rel~="apple-touch-icon" i], link[rel~="apple-touch-icon-precomposed" i]';
    return Array.from(document.querySelectorAll(selector)).map(link => ({
        href: link.href,
        rel: link.rel,
        sizes: link.getAttribute('sizes') || '',
        type: link.type || ''
    }));
    """

    /// Icônes déclarées par la page affichée dans `webView`. Le script tourne dans un monde JavaScript
    /// séparé, que la page ne peut pas modifier.
    @MainActor
    static func extract(from webView: WKWebView) async -> [FaviconCandidate] {
        let result = try? await webView.callAsyncJavaScript(extractionScript, contentWorld: .defaultClient)
        let links = result as? [[String: Any]] ?? []
        return links.compactMap(FaviconCandidate.init(dictionary:))
    }
}
