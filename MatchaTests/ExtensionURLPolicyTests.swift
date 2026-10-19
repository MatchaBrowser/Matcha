import Foundation
@testable import Matcha
import Testing

/// Addresses an extension may open (audit E4): web pages, an empty page, its own pages.
struct ExtensionURLPolicyTests {
    private let base = URL(string: "webkit-extension://3f2a9c/")

    @Test(arguments: [
        ("https://example.com/", true),
        ("http://example.com/", true),
        ("about:blank", true),
        ("webkit-extension://3f2a9c/options.html", true),
        ("webkit-extension://autre/options.html", false),
        ("file:///Users/moi/Downloads/page.html", false),
        ("data:text/html,<script>alert(1)</script>", false),
        ("javascript:alert(1)", false),
        ("blob:https://example.com/1234", false),
        ("about:config", false),
        ("matcha-source:https://example.com/", false),
    ])
    func `an extension opens only web pages, an empty page and its own pages`(url: String, allowed: Bool) throws {
        #expect(try ExtensionURLPolicy.allows(#require(URL(string: url)), from: base) == allowed)
    }
}
