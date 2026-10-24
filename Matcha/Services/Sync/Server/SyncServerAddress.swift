import Foundation

/// Address of a sync server as typed in the settings, normalized (`SYNC.md` § 4.1): `https://` added without a
/// scheme, scheme and host in lowercase, default port removed, path kept without a final `/`, `?` or `#`. HTTPS is
/// required, except for this Mac (`localhost`, `127.0.0.1`, `::1`). The user doesn't type `/v1`: it is added. Pure
/// type.
nonisolated struct SyncServerAddress: Codable, Hashable, Sendable {
    /// Normalized form, the one kept in the keychain and the recovery kit (“https://sync.example.com/api”).
    let normalized: String

    enum Problem: Error, Equatable {
        case invalid
        /// `http` for another host than this Mac.
        case insecure
    }

    /// Address read from what the user typed.
    static func parse(_ text: String) -> Result<SyncServerAddress, Problem> {
        var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            return .failure(.invalid)
        }
        if !typed.contains("://") {
            typed = "https://" + typed
        }
        guard var components = URLComponents(string: typed), let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty, ["http", "https"].contains(scheme)
        else {
            return .failure(.invalid)
        }
        if scheme == "http", !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) {
            return .failure(.insecure)
        }
        components.scheme = scheme
        components.host = host
        if components.port == (scheme == "https" ? 443 : 80) {
            components.port = nil
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/v1") {
            path.removeLast(3)
        }
        components.path = path
        guard let url = components.url else {
            return .failure(.invalid)
        }
        return .success(SyncServerAddress(normalized: url.absoluteString))
    }

    /// Base of the API routes (“…/v1”).
    var apiBase: URL? {
        URL(string: normalized + "/v1")
    }

    /// Host shown in the interface.
    var displayName: String {
        URLComponents(string: normalized)?.host ?? normalized
    }
}
