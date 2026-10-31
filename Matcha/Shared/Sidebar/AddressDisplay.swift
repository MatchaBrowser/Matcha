import Foundation

/// Short address of a page: text of the address pill and subtitle of the tabs in the command
/// bar.
nonisolated enum AddressDisplay {
    /// The domain without “www.” (with the port if there is one), the file name for a `file:`
    /// address, otherwise the whole address (`about:blank`).
    static func short(for url: URL?) -> String {
        guard let url else {
            return ""
        }
        if url.isFileURL {
            return url.lastPathComponent
        }
        guard let host = url.host(), !host.isEmpty else {
            return url.absoluteString
        }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return url.port.map { "\(domain):\($0)" } ?? domain
    }
}
