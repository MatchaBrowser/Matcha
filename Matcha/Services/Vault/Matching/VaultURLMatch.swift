import Foundation

/// The rule of a login (`match` in its overview, `VAULT.md` § 8.2): which pages its addresses (`urls`) select.
/// Whatever the rule, the scheme is `http` or `https`, and a login saved in `https` is never offered on an `http`
/// page (`VaultURLMatcher`). Pure type.
nonisolated enum VaultURLMatch: String, Codable, Sendable, CaseIterable {
    /// The default: the page's host has the same registrable domain as one of the addresses (“www.example.co.uk” for
    /// “accounts.example.co.uk”, but not “alice.github.io” for “bob.github.io”); the port doesn't count.
    case site
    /// The page's host and port are those of one of the addresses.
    case host
    /// The page's origin is that of one of the addresses, and its path is the same (query and fragment left out).
    case page
}

/// How a page, or a frame, matches a login (`VaultURLMatcher`). Pure type.
nonisolated enum VaultURLMatchResult: Equatable, Sendable {
    /// The login is not for this page.
    case noMatch
    /// The login is for this page, served in `https`.
    case match
    /// The login, saved in `http`, is for this page, served in `http`: it is filled with a warning (§ 8.2).
    case insecureMatch

    /// The login may be filled on the page, with a warning or not.
    var isMatch: Bool {
        self != .noMatch
    }
}
