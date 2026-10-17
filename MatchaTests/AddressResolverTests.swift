import Foundation
@testable import Matcha
import Testing

struct AddressResolverTests {
    private let resolver = AddressResolver(searchEngine: .google)

    private func search(_ encodedQuery: String) -> String {
        "https://www.google.com/search?q=\(encodedQuery)"
    }

    // MARK: Cas imposés par le plan

    @Test func `domain gets https`() {
        #expect(resolver.resolve("apple.com")?.absoluteString == "https://apple.com")
    }

    @Test func `full url is kept as is`() {
        #expect(resolver.resolve("https://a.b/c")?.absoluteString == "https://a.b/c")
    }

    @Test func `localhost with port gets http`() {
        #expect(resolver.resolve("localhost:3000")?.absoluteString == "http://localhost:3000")
    }

    @Test func `ip address gets http`() {
        #expect(resolver.resolve("192.168.1.1")?.absoluteString == "http://192.168.1.1")
    }

    @Test func `sentence is searched`() {
        #expect(resolver.resolve("comment faire du pain")?.absoluteString == search("comment%20faire%20du%20pain"))
    }

    @Test func `dot with space is searched`() {
        #expect(resolver.resolve("swift 6.4")?.absoluteString == search("swift%206.4"))
    }

    // MARK: Schémas

    @Test(arguments: [
        "http://example.com/a?b=c#d",
        "HTTPS://Example.com",
        "file:///Users/moi/page.html",
        "about:blank",
    ])
    func `direct schemes are kept`(input: String) {
        #expect(resolver.resolve(input)?.absoluteString == input)
    }

    @Test func `unknown scheme is searched`() {
        #expect(resolver.resolve("mailto:moi@example.com")?.absoluteString == search("mailto%3Amoi%40example.com"))
    }

    // MARK: Hôtes

    @Test(arguments: [
        ("www.apple.com", "https://www.apple.com"),
        ("apple.com/fr/mac?x=1#haut", "https://apple.com/fr/mac?x=1#haut"),
        ("example.com:8443/admin", "https://example.com:8443/admin"),
        ("apple.com.", "https://apple.com."),
        ("my-site.co.uk", "https://my-site.co.uk"),
        ("localhost", "http://localhost"),
        ("LOCALHOST:8080/api", "http://LOCALHOST:8080/api"),
        ("10.0.0.1:8080", "http://10.0.0.1:8080"),
        ("[::1]:8080", "http://[::1]:8080"),
        ("imprimante.local", "http://imprimante.local"),
        ("app.localhost:5173", "http://app.localhost:5173"),
    ])
    func `host like inputs get a scheme`(input: String, expected: String) {
        #expect(resolver.resolve(input)?.absoluteString == expected)
    }

    @Test(arguments: [
        "6.4",
        "1.2.3",
        "256.1.1.1.1",
        "moi@example.com",
        "apple.com:abc",
        "apple.com:99999",
        "-apple.com",
        ".com",
        "com.",
        "swift",
        "example.com/un chemin",
    ])
    func `non host inputs are searched`(input: String) {
        let url = resolver.resolve(input)
        #expect(url?.absoluteString.hasPrefix("https://www.google.com/search?q=") == true)
    }

    // MARK: Divers

    @Test func `surrounding whitespace is trimmed`() {
        #expect(resolver.resolve("  apple.com \n")?.absoluteString == "https://apple.com")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func `empty input gives nil`(input: String) {
        #expect(resolver.resolve(input) == nil)
    }

    @Test func `search encodes reserved and accented characters`() {
        #expect(resolver.resolve("c++ & café #1")?.absoluteString == search("c%2B%2B%20%26%20caf%C3%A9%20%231"))
    }

    // MARK: Interprétation

    @Test(arguments: [
        ("apple.com", AddressInterpretation.address(URL(string: "https://apple.com")!)),
        ("localhost:3000", .address(URL(string: "http://localhost:3000")!)),
        ("about:blank?one", .address(URL(string: "about:blank?one")!)),
        ("pain au levain", .search(URL(string: "https://www.google.com/search?q=pain%20au%20levain")!)),
        ("6.4", .search(URL(string: "https://www.google.com/search?q=6.4")!)),
    ])
    func `interpret tells addresses from searches`(input: String, expected: AddressInterpretation) {
        #expect(resolver.interpret(input) == expected)
    }

    @Test(arguments: ["", "  ", "\n\t"])
    func `interpret gives nil for empty text`(input: String) {
        #expect(resolver.interpret(input) == nil)
    }

    @Test(arguments: [
        "apple.com", "https://a.b/c", "localhost:3000", "192.168.1.1", "comment faire du pain", "swift 6.4",
        "http://example.com/a?b=c#d", "HTTPS://Example.com", "file:///Users/moi/page.html", "about:blank",
        "mailto:moi@example.com", "www.apple.com", "apple.com/fr/mac?x=1#haut", "example.com:8443/admin",
        "apple.com.", "my-site.co.uk", "localhost", "LOCALHOST:8080/api", "10.0.0.1:8080", "[::1]:8080",
        "imprimante.local", "app.localhost:5173", "6.4", "1.2.3", "256.1.1.1.1", "moi@example.com",
        "apple.com:abc", "apple.com:99999", "-apple.com", ".com", "com.", "swift", "example.com/un chemin",
        "  apple.com \n", "", "   ", "\n\t", "c++ & café #1",
    ])
    func `resolve returns the interpreted url`(input: String) {
        #expect(resolver.resolve(input) == resolver.interpret(input)?.url)
    }

    @Test func `uses chosen search engine`() {
        let duck = AddressResolver(searchEngine: .duckDuckGo)
        #expect(duck.resolve("pain")?.absoluteString == "https://duckduckgo.com/?q=pain")
        let bing = AddressResolver(searchEngine: .bing)
        #expect(bing.resolve("pain")?.absoluteString == "https://www.bing.com/search?q=pain")
    }
}
