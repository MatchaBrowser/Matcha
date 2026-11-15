import Foundation

/// The Public Suffix List (https://publicsuffix.org), ICANN and private sections alike, which tells the registrable
/// domain of a host (`VAULT.md` § 8.2, R7): “alice.github.io” and “bob.github.io” are two sites, “www.example.co.uk”
/// and “accounts.example.co.uk” one. It follows the list's algorithm (https://github.com/publicsuffix/list/wiki/Format):
/// normal rules, wildcards “*.” (always the leftmost label), exceptions “!”, which prevail, and the default rule “*”.
/// Rules and hosts are compared lowercased, in ASCII (punycode), without a final dot. An IP address is not a domain:
/// the caller takes it whole before asking (`VaultURLMatcher`). Built once from the list shipped in the app, with one
/// set per kind of rule for lookups in a few hashes. Pure type.
nonisolated struct PublicSuffixList: Sendable {
    enum LoadError: Error, Equatable {
        /// The list is missing from the app's resources.
        case missingFile
        /// The file is not UTF-8 text.
        case unreadable
    }

    static let resourceName = "public_suffix_list"
    static let resourceExtension = "dat"
    /// Folder of the list in the sources; Xcode copies resources flat, so the bundle's root is searched too.
    static let subdirectory = "PublicSuffix"
    /// Ceiling of the file (TR2): the list is about 340 KB.
    static let maximumSize = 2 * 1024 * 1024

    /// Normal rules (“co.uk”).
    private var rules: Set<String> = []
    /// Wildcard rules, without their “*.” (“*.ck” is kept as “ck”).
    private var wildcards: Set<String> = []
    /// Exception rules, without their “!” (“!www.ck” is kept as “www.ck”).
    private var exceptions: Set<String> = []

    /// Number of rules read, of all kinds.
    var ruleCount: Int {
        rules.count + wildcards.count + exceptions.count
    }

    /// List read from `text` in the list's format: one rule per line, only what comes before the first whitespace;
    /// comments (“//”) and blank lines skipped. A rule in Unicode is converted to punycode; one that can't be (an empty
    /// label) is skipped.
    init(text: String) {
        for line in text.utf8.split(separator: UInt8(ascii: "\n")) {
            let token = line.drop(while: Self.isWhitespace).prefix { !Self.isWhitespace($0) }
            guard !token.isEmpty, !token.starts(with: "//".utf8) else {
                continue
            }
            add(String(Substring(token)))
        }
    }

    /// The list shipped in `bundle`'s resources, read with a ceiling of `maximumSize` bytes.
    static func bundled(in bundle: Bundle) throws -> PublicSuffixList {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: subdirectory)
            ?? bundle.url(forResource: resourceName, withExtension: resourceExtension)
        else {
            throw LoadError.missingFile
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        guard data.count <= maximumSize else {
            throw BoundedRead.TooLarge()
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw LoadError.unreadable
        }
        return PublicSuffixList(text: text)
    }

    /// Adds rule `token` to the set of its kind. The rule “*” alone is the default rule, which always applies.
    private mutating func add(_ token: String) {
        if token.hasPrefix("!") {
            Self.insert(token.dropFirst(), into: &exceptions)
        } else if token.hasPrefix("*.") {
            Self.insert(token.dropFirst(2), into: &wildcards)
        } else if token != "*" {
            Self.insert(token[...], into: &rules)
        }
    }

    /// Adds `rule` to `set` in canonical form (`canonicalHost(_:)`); skipped if it has none.
    private static func insert(_ rule: Substring, into set: inout Set<String>) {
        if let canonical = canonicalHost(String(rule)) {
            set.insert(canonical)
        }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\r")
    }

    // MARK: Lookups

    /// `host` as the list compares it: lowercased, in ASCII (each non-ASCII label as “xn--” and its punycode), without
    /// a final dot. Nil if it is empty or has an empty label (“.com”, “a..b”), or can't be encoded.
    static func canonicalHost(_ host: String) -> String? {
        guard var ascii = Punycode.asciiHost(host) else {
            return nil
        }
        if ascii.hasSuffix(".") {
            ascii.removeLast()
        }
        guard !ascii.isEmpty, !ascii.hasPrefix("."), !ascii.hasSuffix("."), !ascii.contains("..") else {
            return nil
        }
        return ascii
    }

    /// The public suffix of `host` (“co.uk” for “www.example.co.uk”, “example” for a top-level domain the list
    /// doesn't know), in canonical form; nil if `host` is not a valid name (`canonicalHost(_:)`).
    func publicSuffix(of host: String) -> String? {
        guard let canonical = Self.canonicalHost(host) else {
            return nil
        }
        let labels = canonical.split(separator: ".")
        return labels.suffix(suffixLabelCount(of: labels)).joined(separator: ".")
    }

    /// The registrable domain of `host`: its public suffix and the label before it (“example.co.uk” for
    /// “www.example.co.uk”), in canonical form. Nil if `host` is itself a public suffix (“co.uk”, “github.io”, a
    /// single label), or is not a valid name.
    func registrableDomain(of host: String) -> String? {
        guard let canonical = Self.canonicalHost(host) else {
            return nil
        }
        let labels = canonical.split(separator: ".")
        let count = suffixLabelCount(of: labels)
        guard labels.count > count else {
            return nil
        }
        return labels.suffix(count + 1).joined(separator: ".")
    }

    /// True if `host` is itself a public suffix (“co.uk”, “github.io”, “com”, a single label).
    func isPublicSuffix(_ host: String) -> Bool {
        Self.canonicalHost(host) != nil && registrableDomain(of: host) == nil
    }

    /// Number of labels of the public suffix of `labels` (canonical, non-empty), by the list's algorithm: a matching
    /// exception prevails, minus its leftmost label; otherwise the matching rule with the most labels, a wildcard
    /// counting the label it stands for; otherwise the default rule “*”, one label.
    private func suffixLabelCount(of labels: [Substring]) -> Int {
        var longest = 1
        for start in labels.indices {
            let length = labels.count - start
            let suffix = labels[start...].joined(separator: ".")
            if exceptions.contains(suffix) {
                return length - 1
            }
            if start > 0, length + 1 > longest, wildcards.contains(suffix) {
                longest = length + 1
            }
            if length > longest, rules.contains(suffix) {
                longest = length
            }
        }
        return longest
    }
}
