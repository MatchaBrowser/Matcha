import Foundation
@testable import Matcha
import Testing

/// Address bar of a sign-in window (task 5.8): the requesting site, and whether the connection is encrypted.
struct PopupAddressTests {
    private func address(_ text: String) -> PopupAddress {
        PopupAddress(url: URL(string: text))
    }

    @Test func `a secure site shows its host with a lock`() {
        let google = address("https://accounts.google.com/o/oauth2/v2/auth?client_id=1&scope=email")
        #expect(google == PopupAddress(text: "accounts.google.com", security: .secure))
        #expect(address("https://www.paypal.com/checkoutnow").text == "paypal.com")
        #expect(address("https://appleid.apple.com:8443/auth").text == "appleid.apple.com:8443")
    }

    @Test func `an http site is not secure`() {
        #expect(address("http://banque.example/login") == PopupAddress(text: "banque.example", security: .notSecure))
        #expect(address("http://[::1]:3000/") == PopupAddress(text: "[::1]:3000", security: .notSecure))
    }

    /// Neither padlock nor warning outside a site; never the content of a `data:` address.
    @Test func `other pages show what they are, without a security state`() {
        #expect(address("about:blank") == PopupAddress(text: "about:blank", security: .none))
        #expect(address("data:text/html,<h1>Connexion</h1>") == PopupAddress(text: "data:", security: .none))
        #expect(address("blob:https://example.com/1234") == PopupAddress(text: "blob:", security: .none))
        #expect(PopupAddress(url: URL(fileURLWithPath: "/tmp/page.html")) == PopupAddress(text: "page.html", security: .none))
        #expect(address("obtest://pages/connexion") == PopupAddress(text: "obtest://pages", security: .none))
        #expect(PopupAddress(url: nil) == PopupAddress(text: "", security: .none))
    }
}
