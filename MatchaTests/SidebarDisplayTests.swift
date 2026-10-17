import Foundation
@testable import Matcha
import Testing

struct SidebarDisplayTests {
    @Test(arguments: [
        ("https://www.apple.com/fr/mac/", "apple.com"),
        ("https://developer.apple.com/documentation", "developer.apple.com"),
        ("http://localhost:3000/api", "localhost:3000"),
        ("about:blank", "about:blank"),
        ("file:///Users/moi/page.html", "page.html"),
    ])
    func `address shows the short domain`(address: String, expected: String) {
        #expect(AddressDisplay.short(for: URL(string: address)) == expected)
    }

    @Test func `no address shows nothing`() {
        #expect(AddressDisplay.short(for: nil) == "")
    }

    @Test(arguments: [("www.apple.com", "A"), ("github.com", "G"), ("éditions.fr", "É"), ("", "?")])
    func `placeholder shows the domain initial`(host: String, expected: String) {
        #expect(FaviconPlaceholder.initial(for: host) == expected)
    }

    @Test func `placeholder without host shows a question mark`() {
        #expect(FaviconPlaceholder.initial(for: nil) == "?")
    }

    @Test func `placeholder hue is stable and spread`() {
        let hue = FaviconPlaceholder.hue(for: "apple.com")
        #expect(hue == FaviconPlaceholder.hue(for: "apple.com"))
        #expect((0 ..< 1).contains(hue))
        #expect(hue != FaviconPlaceholder.hue(for: "github.com"))
    }
}
