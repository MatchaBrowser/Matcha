import Foundation

/// Scope of a linked note: the page it was written on, or every page of its site.
nonisolated enum NoteLinkScope: String, CaseIterable, Sendable {
    case page
    case site
}

/// Page a note is linked to (task 12.1, `SYNC.md` § 2.10): the address it was written on, the key that finds it again,
/// its scope and the page's title then. Pure type.
nonisolated struct NoteLink: Hashable, Sendable {
    /// Address the note was written on (http or https), shown and opened by the library.
    let url: URL
    /// `NotePageKey` for a page, the site (`SiteDomain`, as for zooms) for a site.
    let key: String
    let scope: NoteLinkScope
    /// Title of the page when the note was linked; nil if it had none.
    let title: String?

    /// Link to the page at `url` with this scope; nil outside http and https.
    init?(url: URL, scope: NoteLinkScope, title: String?) {
        guard let key = Self.key(for: url, scope: scope) else {
            return nil
        }
        self.url = url
        self.key = key
        self.scope = scope
        self.title = title.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Link read back, saved or received: the key is taken as it is, never computed again from the address (the rules
    /// may change from one version to the next). Nil if a field is missing or unreadable.
    init?(storedURL: String?, key: String?, scope: String?, title: String?) {
        guard let storedURL, let url = URL(string: storedURL), SiteOrigin.web(of: url) != nil,
              let key, !key.isEmpty,
              let scope = scope.flatMap(NoteLinkScope.init(rawValue:))
        else {
            return nil
        }
        self.url = url
        self.key = key
        self.scope = scope
        self.title = title.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Key of the page at `url` for this scope; nil outside http and https.
    static func key(for url: URL, scope: NoteLinkScope) -> String? {
        switch scope {
        case .page: NotePageKey.key(for: url)
        case .site: SiteDomain.site(of: url)
        }
    }
}
