import Foundation

/// Choix de l'icône d'une page parmi celles qu'elle déclare.
nonisolated enum FaviconSelector {
    /// Taille retenue pour une icône vectorielle ou déclarée « any ».
    static let scalableSize = 1024
    /// Taille habituelle d'une `apple-touch-icon` qui ne la précise pas.
    static let appleTouchIconSize = 180
    /// Taille supposée d'une icône sans indication.
    static let unknownSize = 16

    /// Adresses à essayer, de la meilleure à la moins bonne : la plus grande d'abord, à taille égale
    /// dans l'ordre de la page, puis `/favicon.ico` à la racine du site. Sans doublon.
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

    /// Taille estimée d'une icône, en pixels.
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

    /// Plus grande taille de l'attribut `sizes` (« 16x16 32x32 » → 32), nil s'il n'en donne aucune.
    static func largestDeclaredSize(_ sizes: String) -> Int? {
        let tokens = sizes.lowercased().split(separator: " ")
        if tokens.contains("any") {
            return scalableSize
        }
        return tokens.compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max()
    }

    /// `/favicon.ico` à la racine du site de `pageURL`, pour une page web.
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
