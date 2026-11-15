import Foundation
@testable import Matcha
import Testing

/// The public suffix list shipped in the app (`VAULT.md` § 8.2, R7): the official test cases, the list's format and
/// its algorithm on small lists, and the ceiling on the file.
struct PublicSuffixListTests {
    /// Read once: the list has some ten thousand rules.
    private static let bundled = Result { try PublicSuffixList.bundled(in: .main) }

    /// The `checkPublicSuffix(input, registrableDomain)` cases of the list's `tests/test_psl.txt`, all of them, checked
    /// against the bundled list (version 2026-11-06, which agrees with every case). Left out: the `null` input (a host
    /// here is never nil) and the `local` cases, commented out in the file. No case needs UTS #46 beyond
    /// lowercasing; the results are in punycode, so those of the IDN cases are written in punycode, matching the
    /// file's punycoded cases.
    @Test(arguments: [
        // Mixed case.
        ("COM", nil), ("example.COM", "example.com"), ("WwW.example.COM", "example.com"),
        // Leading dot.
        (".com", nil), (".example", nil), (".example.com", nil), (".example.example", nil),
        // Unlisted TLD.
        ("example", nil), ("example.example", "example.example"), ("b.example.example", "example.example"),
        ("a.b.example.example", "example.example"),
        // TLD with only 1 rule.
        ("biz", nil), ("domain.biz", "domain.biz"), ("b.domain.biz", "domain.biz"), ("a.b.domain.biz", "domain.biz"),
        // TLD with some 2-level rules.
        ("com", nil), ("example.com", "example.com"), ("b.example.com", "example.com"), ("a.b.example.com", "example.com"),
        ("uk.com", nil), ("example.uk.com", "example.uk.com"), ("b.example.uk.com", "example.uk.com"),
        ("a.b.example.uk.com", "example.uk.com"), ("test.ac", "test.ac"),
        // TLD with only 1 (wildcard) rule.
        ("mm", nil), ("c.mm", nil), ("b.c.mm", "b.c.mm"), ("a.b.c.mm", "b.c.mm"),
        // More complex TLD.
        ("jp", nil), ("test.jp", "test.jp"), ("www.test.jp", "test.jp"), ("ac.jp", nil), ("test.ac.jp", "test.ac.jp"),
        ("www.test.ac.jp", "test.ac.jp"), ("kyoto.jp", nil), ("test.kyoto.jp", "test.kyoto.jp"), ("ide.kyoto.jp", nil),
        ("b.ide.kyoto.jp", "b.ide.kyoto.jp"), ("a.b.ide.kyoto.jp", "b.ide.kyoto.jp"), ("c.kobe.jp", nil),
        ("b.c.kobe.jp", "b.c.kobe.jp"), ("a.b.c.kobe.jp", "b.c.kobe.jp"), ("city.kobe.jp", "city.kobe.jp"),
        ("www.city.kobe.jp", "city.kobe.jp"),
        // TLD with a wildcard rule and exceptions.
        ("ck", nil), ("test.ck", nil), ("b.test.ck", "b.test.ck"), ("a.b.test.ck", "b.test.ck"), ("www.ck", "www.ck"),
        ("www.www.ck", "www.ck"),
        // US K12.
        ("us", nil), ("test.us", "test.us"), ("www.test.us", "test.us"), ("ak.us", nil), ("test.ak.us", "test.ak.us"),
        ("www.test.ak.us", "test.ak.us"), ("k12.ak.us", nil), ("test.k12.ak.us", "test.k12.ak.us"),
        ("www.test.k12.ak.us", "test.k12.ak.us"),
        // IDN labels (results in punycode).
        ("食狮.com.cn", "xn--85x722f.com.cn"), ("食狮.公司.cn", "xn--85x722f.xn--55qx5d.cn"),
        ("www.食狮.公司.cn", "xn--85x722f.xn--55qx5d.cn"), ("shishi.公司.cn", "shishi.xn--55qx5d.cn"), ("公司.cn", nil),
        ("食狮.中国", "xn--85x722f.xn--fiqs8s"), ("www.食狮.中国", "xn--85x722f.xn--fiqs8s"), ("shishi.中国", "shishi.xn--fiqs8s"),
        ("中国", nil),
        // Same as above, but punycoded.
        ("xn--85x722f.com.cn", "xn--85x722f.com.cn"), ("xn--85x722f.xn--55qx5d.cn", "xn--85x722f.xn--55qx5d.cn"),
        ("www.xn--85x722f.xn--55qx5d.cn", "xn--85x722f.xn--55qx5d.cn"), ("shishi.xn--55qx5d.cn", "shishi.xn--55qx5d.cn"),
        ("xn--55qx5d.cn", nil), ("xn--85x722f.xn--fiqs8s", "xn--85x722f.xn--fiqs8s"),
        ("www.xn--85x722f.xn--fiqs8s", "xn--85x722f.xn--fiqs8s"), ("shishi.xn--fiqs8s", "shishi.xn--fiqs8s"),
        ("xn--fiqs8s", nil),
    ] as [(String, String?)])
    func `the official test cases pass`(host: String, registrableDomain: String?) throws {
        let list = try Self.bundled.get()
        #expect(list.registrableDomain(of: host) == registrableDomain)
    }

    @Test func `the bundled list has both sections`() throws {
        let list = try Self.bundled.get()
        #expect(list.ruleCount > 10000)
        // ICANN section.
        #expect(list.registrableDomain(of: "accounts.example.co.uk") == "example.co.uk")
        #expect(list.publicSuffix(of: "www.example.co.uk") == "co.uk")
        // Private section: page hosts are suffixes, so each of their sites is a site.
        #expect(list.registrableDomain(of: "alice.github.io") == "alice.github.io")
        #expect(list.registrableDomain(of: "www.alice.github.io") == "alice.github.io")
        #expect(list.isPublicSuffix("github.io"))
        #expect(list.isPublicSuffix("co.uk"))
        #expect(!list.isPublicSuffix("example.co.uk"))
        #expect(list.registrableDomain(of: "www.example.com.") == "example.com")
    }

    @Test func `the format is read rule by rule`() {
        let list = PublicSuffixList(text: """
        // A comment, then a blank line.

        example
        *.wild.example\r
        !keep.wild.example
        short.example   anything after a space is ignored
        公司.example
        *
        """)
        #expect(list.ruleCount == 5)
        #expect(list.registrableDomain(of: "a.short.example") == "a.short.example")
        #expect(list.registrableDomain(of: "b.a.wild.example") == "b.a.wild.example")
        #expect(list.publicSuffix(of: "b.a.wild.example") == "a.wild.example")
        // An exception prevails over the wildcard, without its leftmost label.
        #expect(list.registrableDomain(of: "x.keep.wild.example") == "keep.wild.example")
        // A wildcard needs a label of its own: “wild.example” itself falls under “example”.
        #expect(list.registrableDomain(of: "wild.example") == "wild.example")
        // A Unicode rule is compared in punycode, whatever form the host comes in.
        #expect(list.registrableDomain(of: "a.公司.example") == "a.xn--55qx5d.example")
        #expect(list.registrableDomain(of: "a.xn--55qx5d.example") == "a.xn--55qx5d.example")
    }

    @Test func `without a matching rule the default rule takes the last label`() {
        let list = PublicSuffixList(text: "")
        #expect(list.publicSuffix(of: "a.b.c") == "c")
        #expect(list.registrableDomain(of: "a.b.c") == "b.c")
        #expect(list.registrableDomain(of: "localhost") == nil)
        #expect(list.isPublicSuffix("intranet"))
    }

    @Test func `hosts are compared lowercased, in punycode and without a final dot`() {
        #expect(PublicSuffixList.canonicalHost("WWW.Example.COM.") == "www.example.com")
        #expect(PublicSuffixList.canonicalHost("BÜCHER.de") == "xn--bcher-kva.de")
        #expect(PublicSuffixList.canonicalHost("") == nil)
        #expect(PublicSuffixList.canonicalHost(".") == nil)
        #expect(PublicSuffixList.canonicalHost(".com") == nil)
        #expect(PublicSuffixList.canonicalHost("a..b") == nil)
        #expect(PublicSuffixList.canonicalHost("example.com..") == nil)
    }

    @Test func `a missing list or one over the ceiling is refused`() throws {
        try withBundle(containing: nil) { bundle in
            #expect(throws: PublicSuffixList.LoadError.missingFile) { try PublicSuffixList.bundled(in: bundle) }
        }
        try withBundle(containing: Data(repeating: UInt8(ascii: "a"), count: PublicSuffixList.maximumSize + 1)) { bundle in
            #expect(throws: BoundedRead.TooLarge.self) { try PublicSuffixList.bundled(in: bundle) }
        }
        try withBundle(containing: Data([0x63, 0x6F, 0xFF, 0x0A])) { bundle in
            #expect(throws: PublicSuffixList.LoadError.unreadable) { try PublicSuffixList.bundled(in: bundle) }
        }
        try withBundle(containing: Data("example\n".utf8)) { bundle in
            let list = try PublicSuffixList.bundled(in: bundle)
            #expect(list.ruleCount == 1)
        }
    }

    /// Runs `body` with a bundle of its own folder (a bundle caches the files it has looked for), holding `list` as its
    /// public suffix list if there is one.
    private func withBundle(containing list: Data?, _ body: (Bundle) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "psl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        if let list {
            try list.write(to: folder.appending(path: "public_suffix_list.dat"))
        }
        try body(#require(Bundle(url: folder)))
    }
}
