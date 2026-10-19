import Foundation
@testable import Matcha
import Testing

/// Fields of synced records (task 7.4, `SYNC.md` § 2.1, § 2.5 and § 2.6): JSON round trip, unknown values ignored.
struct SyncFieldsTests {
    private let profile = UUID()
    private let space = UUID()

    private func roundTrip(_ fields: SyncFields) -> SyncFields? {
        SyncFields(json: fields.json, type: fields.type)
    }

    private func object(_ text: String) throws -> SyncJSON {
        try SyncCoding.decoder().decode(SyncJSON.self, from: Data(text.utf8))
    }

    private func emptyTodayTab() -> SyncTabFields {
        SyncTabFields(place: .today, url: nil, title: nil, order: 0, profileId: nil, spaceId: space, folderId: nil, lastActivity: nil)
    }

    private func sidebarFields() throws -> [SyncFields] {
        let theme = SpaceTheme(name: "matcha", colors: [.white, .black])
        var tab = emptyTodayTab()
        tab.url = URL(string: "https://example.com/a?b=1")
        tab.title = "Exemple"
        tab.lastActivity = SyncCoding.date(milliseconds: 1_760_000_000_123)
        return [
            .profile(SyncProfileFields(name: "Personnel", order: 0)),
            .space(SyncSpaceFields(name: "Perso", symbol: "emoji:🍵", theme: theme, order: 2, profileId: profile)),
            .folder(SyncFolderFields(
                name: "Projets",
                order: 1,
                isCollapsed: true,
                spaceId: space,
                parentId: nil,
                icon: "symbol:briefcase",
                textColor: "#112233",
                backgroundColor: nil,
            )),
            .tab(tab),
            .tab(emptyTodayTab()),
        ]
    }

    private var otherFields: [SyncFields] {
        let permission = SyncSitePermissionFields(origin: "https://meet.google.com", kind: "camera", decision: "allow", profileId: profile)
        return [
            .webExtension(SyncExtensionFields(
                identifier: "dark-reader",
                name: "Dark Reader",
                version: "4.9.99",
                source: .package(blobID: UUID(), blobKey: "Y2zDqQ==", sha256: "ab12", size: 845_312, fileName: "darkreader.xpi"),
                isEnabled: true,
                allowsPrivateWindows: false,
                showsButton: true,
                grantedPermissions: ["tabs": nil, "storage": SyncCoding.date(milliseconds: 1_900_000_000_000)],
                deniedPermissions: [:],
                grantedMatchPatterns: ["*://*/*": nil],
                deniedMatchPatterns: [:],
            )),
            .setting(SyncSettingFields(key: "searchEngine", value: .string("duckDuckGo"))),
            .setting(SyncSettingFields(key: "tabSuspensionDelay", value: .number(60))),
            .setting(SyncSettingFields(key: "showsHomeButton", value: .bool(true))),
            .sitePermission(permission),
            .siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.25)),
        ]
    }

    @Test func `each type goes and comes back`() throws {
        for fields in try sidebarFields() + otherFields {
            #expect(roundTrip(fields) == fields)
        }
    }

    @Test func `unknown values make the record ignored`() throws {
        #expect(try SyncFields(json: object(#"{"place":"archived","order":0}"#), type: .tab) == nil)
        #expect(try SyncFields(json: object(#"{"key":"windowFrame","value":"0 0 10 10"}"#), type: .setting) == nil)
        #expect(try SyncFields(json: object(#"{"key":"searchEngine","value":"yahoo"}"#), type: .setting) == nil)
        #expect(try SyncFields(json: object(#"{"key":"tabSuspensionDelay","value":45}"#), type: .setting) == nil)
        #expect(try SyncFields(json: object(#"{"key":"showsHomeButton","value":"yes"}"#), type: .setting) == nil)
        let location = #"{"origin":"https://a.b","kind":"location","decision":"allow"}"#
        #expect(try SyncFields(json: object(location), type: .sitePermission) == nil)
        let ask = #"{"origin":"https://a.b","kind":"camera","decision":"ask"}"#
        #expect(try SyncFields(json: object(ask), type: .sitePermission) == nil)
        #expect(try SyncFields(json: object(#"{"site":"example.com","level":5}"#), type: .siteZoom) == nil)
        #expect(try SyncFields(json: object(#"{"name":"Sans rang"}"#), type: .profile) == nil)
    }

    @Test func `unknown fields are ignored, and kept by a modification`() throws {
        let received = try object(##"{"name":"Perso","order":1,"pinnedColor":"#FF0000"}"##)
        let fields = try #require(SyncFields(json: received, type: .profile))
        #expect(fields == .profile(SyncProfileFields(name: "Perso", order: 1)))
        let changed = SyncFields.profile(SyncProfileFields(name: "Maison", order: 1)).json.keepingUnknownKeys(of: received)
        #expect(changed.objectValue["name"] == .string("Maison"))
        #expect(changed.objectValue["pinnedColor"] == .string("#FF0000"))
    }

    @Test func `settings are read as UserDefaults keeps them`() {
        #expect(SyncedSettings.value(true as NSNumber, for: "showsHomeButton") == .bool(true))
        #expect(SyncedSettings.value("NO", for: "confirmBeforeQuitting") == .bool(false))
        #expect(SyncedSettings.value(1 as NSNumber, for: "showsHomeButton") == nil)
        #expect(SyncedSettings.value(30 as NSNumber, for: "tabSuspensionDelay") == .number(30))
        #expect(SyncedSettings.value("0", for: "tabSuspensionDelay") == .number(0))
        #expect(SyncedSettings.value("bing", for: "searchEngine") == .string("bing"))
        #expect(SyncedSettings.value("bing", for: "sidebarWidth") == nil)
        #expect(SyncedSettings.defaultsValue(of: .number(60)) as? Int == 60)
        #expect(SyncedSettings.keys.contains("homePage"))
        #expect(!SyncedSettings.keys.contains("blocksAdsAndTrackers"))
    }

    @Test func `a today tab that only changed page waits to be stable`() {
        let tab = emptyTodayTab()
        var navigated = tab
        navigated.url = URL(string: "https://example.com")
        navigated.title = "Exemple"
        #expect(navigated.differsOnlyByPage(from: tab))
        var moved = navigated
        moved.order = 4
        #expect(!moved.differsOnlyByPage(from: tab))
        var pinned = navigated
        pinned.place = .pinned
        #expect(!pinned.differsOnlyByPage(from: tab))
    }
}
