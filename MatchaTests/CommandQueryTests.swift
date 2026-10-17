import Foundation
@testable import Matcha
import Testing

struct CommandQueryTests {
    @Test(arguments: [
        ("apple.com", true),
        ("node.js", true),
        ("  www.apple.com ", true),
        ("localhost:3000", false),
        ("192.168.1.1", false),
        ("apple.com/fr", false),
        ("https://a.b", false),
        ("pain", false),
        ("me@x.com", false),
        ("", false),
    ])
    func `bare domains`(text: String, isBareDomain: Bool) {
        #expect(query(text).isBareDomain == isBareDomain)
    }

    @Test func `tokens compact and url forms`() throws {
        let typed = query("  Swift   FORUMS é ")
        #expect(typed.trimmed == "Swift   FORUMS é")
        #expect(typed.folded == "swift forums e")
        #expect(typed.tokens == ["swift", "forums", "e"])
        #expect(typed.compact == "swiftforumse")
        #expect(typed.urlFolded == "swift forums e")
        #expect(typed.isSearch)
        #expect(!typed.isEmpty)

        let address = query("HTTPS://WWW.GitHub.com/apple", engine: .bing)
        #expect(address.urlFolded == "github.com/apple")
        #expect(address.addressKey == "github.com/apple")
        #expect(typed.addressKey == nil)
        #expect(query("https://www.apple.com/").urlFolded == "apple.com")
        #expect(query("/").urlFolded == "/")
        #expect(try address.interpretation == .address(#require(URL(string: "HTTPS://WWW.GitHub.com/apple"))))
        #expect(!address.isSearch)
        #expect(address.searchEngine == .bing)

        let empty = query(" \n ")
        #expect(empty.isEmpty)
        #expect(empty.tokens.isEmpty)
        #expect(empty.interpretation == nil)
        #expect(!empty.isSearch)
    }
}
