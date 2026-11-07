import Foundation

/// Key that finds a page's note again (task 12.1, `SYNC.md` § 2.10): the host (lowercase, without a final dot), the port
/// if it is not the scheme's, the path without a final “/”, and the query without its tracking parameters, sorted by name.
/// No scheme (a page moved from http to https keeps its note), no user, no fragment. “www.” is kept, as in the origins.
/// Nil outside http and https. Pure type.
nonisolated enum NotePageKey {
    /// Parameters that only say where a visit came from; their name is compared in lowercase.
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "igshid", "mc_cid", "mc_eid",
        "_ga", "_gl", "_hsenc", "_hsmi", "mkt_tok", "oly_anon_id", "oly_enc_id", "vero_id", "rb_clickid", "s_cid", "si",
    ]
    /// Prefixes of tracking parameters (`utm_source`, `utm_medium`…).
    static let trackingPrefixes = ["utm_"]

    static func key(for url: URL) -> String? {
        guard let origin = SiteOrigin.web(of: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        var key = origin.host.contains(":") ? "[\(origin.host)]" : origin.host
        if let port = origin.port {
            key += ":\(port)"
        }
        var path = components.percentEncodedPath
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        key += path.isEmpty ? "/" : path
        let query = keptQuery(components.percentEncodedQueryItems ?? [])
        if !query.isEmpty {
            key += "?" + query
        }
        return key
    }

    static func isTracking(_ name: String) -> Bool {
        let name = name.lowercased()
        return trackingParameters.contains(name) || trackingPrefixes.contains { name.hasPrefix($0) }
    }

    /// The parameters that designate the page, sorted by name (the order of the address among equal names), still
    /// percent-encoded.
    private static func keptQuery(_ items: [URLQueryItem]) -> String {
        items.enumerated()
            .filter { !isTracking($0.element.name.removingPercentEncoding ?? $0.element.name) }
            .sorted { ($0.element.name, $0.offset) < ($1.element.name, $1.offset) }
            .map { item in item.element.value.map { "\(item.element.name)=\($0)" } ?? item.element.name }
            .joined(separator: "&")
    }
}
