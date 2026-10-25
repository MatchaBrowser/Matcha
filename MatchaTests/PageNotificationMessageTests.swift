import Foundation
@testable import Matcha
import Testing

/// Messages of the notification script and the decisions it reads (pure types).
@MainActor
struct PageNotificationMessageTests {
    @Test func `messages are read and malformed ones refused`() {
        #expect(PageNotificationMessage(body: ["type": "request"]) == .requestPermission)
        #expect(PageNotificationMessage(body: ["type": "close", "id": "a1"]) == .close(scriptID: "a1"))
        let show = PageNotificationMessage(body: [
            "type": "show",
            "id": "a1",
            "title": "Titre",
            "body": "Texte",
            "tag": "t",
            "silent": true,
        ])
        #expect(show == .show(PageNotificationContent(scriptID: "a1", title: "Titre", body: "Texte", tag: "t", isSilent: true)))
        #expect(PageNotificationMessage(body: ["type": "show", "id": "a1", "title": "Titre"])
            == .show(PageNotificationContent(scriptID: "a1", title: "Titre")))

        #expect(PageNotificationMessage(body: "request") == nil)
        #expect(PageNotificationMessage(body: ["type": "unknown"]) == nil)
        #expect(PageNotificationMessage(body: ["type": "show", "title": "Sans identifiant"]) == nil)
        #expect(PageNotificationMessage(body: ["type": "show", "id": "a1"]) == nil)
        #expect(PageNotificationMessage(body: ["type": "close", "id": ""]) == nil)
    }

    @Test func `a page can't fill the notification center`() {
        let content = PageNotificationContent(
            scriptID: "a1",
            title: String(repeating: "t", count: 5000),
            body: String(repeating: "b", count: 5000),
            tag: String(repeating: "g", count: 5000),
        )
        #expect(content.title.count == PageNotificationContent.maximumTitleLength)
        #expect(content.body.count == PageNotificationContent.maximumBodyLength)
        #expect(content.tag.count == PageNotificationContent.maximumTitleLength)
    }

    @Test func `the state script gives each origin its permission`() {
        #expect(PageNotificationPermission(.allow) == .granted)
        #expect(PageNotificationPermission(.deny) == .denied)
        #expect(PageNotificationPermission(nil) == .default)

        let bridge = PageNotificationScript.bridgeName
        let source = PageNotificationScript.stateSource(isAvailable: true, states: [
            "https://mail.example.com": .granted,
            "http://localhost:8080": .denied,
        ])
        let states = #"{"http:\/\/localhost:8080":"denied","https:\/\/mail.example.com":"granted"}"#
        #expect(source == "window['\(bridge)']?.setStates(true, \(states));")
        #expect(PageNotificationScript.stateSource(isAvailable: false, states: [:]) == "window['\(bridge)']?.setStates(false, {});")
    }
}
