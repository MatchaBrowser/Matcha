import Foundation

/// Site under which a page's zoom is remembered (task 5.4): the registrable domain approximated by `SiteDomain` for
/// a web page (“mail.google.com” and “docs.google.com” share “google.com”; scheme, port and “www.” do not count), a
/// single key for all local files, nothing for the other pages (`about:`, `data:`, `blob:`), which stay at 100%.
nonisolated enum SiteZoomKey {
    /// Key shared by local files: it cannot be a host (`SiteDomain` never gives one with “/”).
    static let localFiles = "file://"

    static func key(for url: URL?) -> String? {
        guard let url else {
            return nil
        }
        if url.isFileURL {
            return localFiles
        }
        return SiteDomain.site(of: url)
    }
}
