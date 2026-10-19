import Foundation

/// Choice of a page's icon among those it declares.
nonisolated enum FaviconSelector {
    /// Size assumed for a vector icon or one declared “any”.
    static let scalableSize = 1024
    /// Usual size of an `apple-touch-icon` that does not specify it.
    static let appleTouchIconSize = 180
    /// Assumed size of an icon without any indication.
    static let unknownSize = 16

    /// Addresses to try, from best to worst: the largest first, in page order for equal sizes, then `/favicon.ico` at
    /// the root of the website. Without duplicates.
    static func urlsToTry(candidates: [FaviconCandidate], pageURL: URL) -> [URL] {
        let ranked = candidates
            .filter { ["http", "https", "data"].contains($0.url.scheme?.lowercased() ?? "") }
            .enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (size(of: lhs.element), size(of: rhs.element))
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element.url)
        var urls: [URL] = []
        for url in ranked + [defaultIconURL(for: pageURL)].compactMap(\.self) where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    /// Estimated size of an icon, in pixels.
    static func size(of candidate: FaviconCandidate) -> Int {
        if let declared = largestDeclaredSize(candidate.sizes) {
            return declared
        }
        if candidate.type.lowercased().contains("svg") || candidate.url.pathExtension.lowercased() == "svg" {
            return scalableSize
        }
        if candidate.rel.lowercased().contains("apple-touch-icon") {
            return appleTouchIconSize
        }
        return unknownSize
    }

    /// Largest size in the `sizes` attribute (“16x16 32x32” → 32), nil if it gives none.
    static func largestDeclaredSize(_ sizes: String) -> Int? {
        let tokens = sizes.lowercased().split(separator: " ")
        if tokens.contains("any") {
            return scalableSize
        }
        return tokens.compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
    }

    /// `/favicon.ico` at the root of the website of `pageURL`, for a web page.
    static func defaultIconURL(for pageURL: URL) -> URL? {
        guard ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false),
              components.host?.isEmpty == false
        else {
            return nil
        }
        components.user = nil
        components.password = nil
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
