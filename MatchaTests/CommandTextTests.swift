import Foundation
@testable import Matcha
import Testing

struct CommandTextTests {
    private func display(_ address: String) -> String {
        CommandText.displayURL(URL(string: address)!)
    }

    private func key(_ address: String) -> String {
        CommandText.urlKey(URL(string: address)!)
    }

    @Test func `fold ignores case accents and width`() {
        #expect(CommandText.fold("CAFÉ  Crème") == "cafe creme")
        #expect(CommandText.fold("ＡＢＣ") == "abc")
        #expect(CommandText.fold("Ångström Über") == "angstrom uber")
    }

    @Test func `fold collapses and trims whitespace`() {
        #expect(CommandText.fold("  pain \t au\n\nlevain  ") == "pain au levain")
        #expect(CommandText.fold("   ") == "")
    }

    @Test func `words split on anything but letters and digits`() {
        #expect(CommandText.words("github.com/apple/swift-6") == ["github", "com", "apple", "swift", "6"])
        #expect(CommandText.words("--").isEmpty)
    }

    @Test func `display url drops scheme www root slash and fragment`() {
        #expect(display("https://www.apple.com/") == "apple.com")
        #expect(display("https://apple.com/fr/#x") == "apple.com/fr")
        #expect(display("http://example.com") == "example.com")
    }

    @Test func `display url keeps non default port path and query`() {
        #expect(display("http://localhost:3000/x?y=1") == "localhost:3000/x?y=1")
        #expect(display("https://a.b:443/") == "a.b")
        #expect(display("http://a.b:80/") == "a.b")
        #expect(display("https://a.b:80/") == "a.b:80")
        #expect(display("https://a.b/caf%C3%A9?q=%C3%A9t%C3%A9") == "a.b/café?q=été")
        #expect(display("http://[::1]:8080/x") == "[::1]:8080/x")
    }

    @Test func `display url of other schemes`() {
        #expect(display("about:blank?one") == "about:blank?one")
        #expect(display("about:blank#one") == "about:blank")
        #expect(display("file:///Users/x/a.html") == "/Users/x/a.html")
    }

    @Test func `url key ignores http versus https and host case`() {
        #expect(key("http://www.Apple.com/") == key("https://apple.com"))
        #expect(key("HTTPS://WWW.APPLE.COM/fr") == "apple.com/fr")
        #expect(key("https://apple.com/fr#haut") == key("https://apple.com/fr/"))
    }

    @Test func `url key keeps the query and the scheme of other urls`() {
        #expect(key("https://a.com/?x=1") != key("https://a.com/?x=2"))
        #expect(key("https://a.com/Page") != key("https://a.com/page"))
        #expect(key("about:blank?one") == "about:blank?one")
        #expect(key("ABOUT:blank") == "about:blank")
        #expect(key("about:blank?one") != key("about:blank?two"))
        #expect(key("file:///Users/x/a.html") == "file:/Users/x/a.html")
    }

    @Test func `url prefixes are stripped`() {
        #expect(CommandText.stripURLPrefixes("https://www.git") == "git")
        #expect(CommandText.stripURLPrefixes("http://example.com") == "example.com")
        #expect(CommandText.stripURLPrefixes("www.apple.com") == "apple.com")
        #expect(CommandText.stripURLPrefixes("swift") == "swift")
        #expect(CommandText.stripURLPrefixes("https://") == "")
    }
}
