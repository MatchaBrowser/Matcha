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

    private func emptyPinnedTab() -> SyncTabFields {
        SyncTabFields(place: .pinned, url: nil, title: nil, order: 0, profileId: nil, spaceId: space, folderId: nil)
    }

    private func sidebarFields() throws -> [SyncFields] {
        let theme = SpaceTheme(name: "matcha", colors: [.white, .black])
        var tab = emptyPinnedTab()
        tab.url = URL(string: "https://example.com/a?b=1")
        tab.title = "Exemple"
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
            .tab(emptyPinnedTab()),
        ]
    }

    private var otherFields: [SyncFields] {
        let permission = SyncSitePermissionFields(origin: "https://meet.google.com", kind: "camera", decision: "allow", profileId: profile)
        return [
            .webExtension(SyncExtensionFields(
                identifier: "dark-reader",
                name: "Dark Reader",
                version: "4.9.99",
                source: .package(
                    blobID: UUID(),
                    blobKey: Data(repeating: 1, count: 32).base64EncodedString(),
                    sha256: String(repeating: "ab", count: 32),
                    size: 845_312,
                    fileName: "darkreader.xpi",
                ),
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
        // A missing parent, an address that isn't web, an incomplete package, a number that isn't an exact integer.
        #expect(try SyncFields(json: object(#"{"name":"Sans profil","symbol":"star.fill","order":0}"#), type: .space) == nil)
        let script = #"{"place":"today","url":"javascript:alert(1)","spaceId":"9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"}"#
        #expect(try SyncFields(json: object(script), type: .tab) == nil)
        let package = #"{"identifier":"x","source":{"kind":"package","blobId":"9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"}}"#
        #expect(try SyncFields(json: object(package), type: .webExtension) == nil)
        #expect(try SyncFields(json: object(#"{"key":"tabSuspensionDelay","value":1e19}"#), type: .setting) == nil)
        #expect(try SyncFields(json: object(#"{"key":"homePage","value":"javascript:alert(1)"}"#), type: .setting) == nil)
        #expect(try SyncFields(json: object(#"{"key":"homePage","value":"localhost:3000"}"#), type: .setting) != nil)
        // An origin not written as SYNC.md § 2.7 says.
        let profileKey = #""profileId":"9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40""#
        let origin = #"{"origin":"https://Meet.Google.com/","kind":"camera","decision":"deny","#
        #expect(try SyncFields(json: object(origin + profileKey + "}"), type: .sitePermission) == nil)
    }

    @Test func `unreadable values take their default value`() throws {
        #expect(try SyncFields(json: object(#"{"name":"Sans rang"}"#), type: .profile) == .profile(SyncProfileFields(
            name: "Sans rang",
            order: 0,
        )))
        let space = #"{"name":7,"order":2.5,"theme":"rouge","profileId":"9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"}"#
        guard case let .space(fields) = try SyncFields(json: object(space), type: .space) else {
            Issue.record("Space ignored")
            return
        }
        #expect(fields.name.isEmpty && fields.symbol == SidebarIcon.defaultSpaceSymbol && fields.theme == nil && fields.order == 2.5)
        #expect(SyncOrder.integer(2.5) == 3 && SyncOrder.integer(1e300) == 1_000_000_000)
        let source = #""source":{"kind":"appExtension","bundleIdentifier":"a","appBundleIdentifier":"b"}"#
        let rights = #"{"identifier":"x","# + source + #","grantedPermissions":{"tabs":null,"storage":"demain"}}"#
        guard case let .webExtension(extensionFields) = try SyncFields(json: object(rights), type: .webExtension) else {
            Issue.record("Extension ignored")
            return
        }
        #expect(extensionFields.grantedPermissions == ["tabs": Date?.none])
        #expect(extensionFields.showsButton && !extensionFields.isEnabled)
    }

    @Test func `unknown fields are ignored, and kept by a modification`() throws {
        let received = try object(##"{"name":"Perso","order":1,"pinnedColor":"#FF0000"}"##)
        let fields = try #require(SyncFields(json: received, type: .profile))
        #expect(fields == .profile(SyncProfileFields(name: "Perso", order: 1)))
        let changed = SyncFieldMerge.merged(
            remote: received,
            local: SyncFields.profile(SyncProfileFields(name: "Maison", order: 1)).json,
            baseline: fields.json,
            knownKeys: SyncRecordType.profile.fieldKeys,
        )
        #expect(changed.objectValue["name"] == .string("Maison"))
        #expect(changed.objectValue["pinnedColor"] == .string("#FF0000"))
    }

    @Test func `only the fields changed here replace the received ones`() throws {
        // A folder moved back to the root here: its parent leaves as null (absent), it isn't put back.
        let folder = SyncFolderFields(name: "Projets", order: 1, isCollapsed: false, spaceId: space, parentId: profile)
        var atRoot = folder
        atRoot.parentId = nil
        let parents = #""spaceId":"\#(space.uuidString)","parentId":"\#(profile.uuidString)""#
        let received = try object(#"{"name":"Renamed elsewhere","order":1,"isCollapsed":false,"# + parents + "}")
        let sent = SyncFieldMerge.merged(
            remote: received,
            local: SyncFields.folder(atRoot).json,
            baseline: SyncFields.folder(folder).json,
            knownKeys: SyncRecordType.folder.fieldKeys,
        )
        #expect(sent.objectValue["parentId"] == nil)
        // The name received and not changed here leaves as it was received.
        #expect(sent.objectValue["name"] == .string("Renamed elsewhere"))
        // Permissions entry by entry: one granted here, one received kept.
        let base = SyncJSON.object(["grantedPermissions": .object(["tabs": .null])])
        let mine = SyncJSON.object(["grantedPermissions": .object(["tabs": .null, "storage": .null])])
        let remote = SyncJSON.object(["grantedPermissions": .object(["tabs": .null, "cookies": .null])])
        let merged = SyncFieldMerge.merged(remote: remote, local: mine, baseline: base, knownKeys: SyncRecordType.webExtension.fieldKeys)
        #expect(merged.objectValue["grantedPermissions"]?.objectValue.keys.sorted() == ["cookies", "storage", "tabs"])
    }

    /// Review SY1: without a baseline, every known field takes this Mac's value, an emptied one included; the unknown
    /// ones stay.
    @Test func `without a baseline, an emptied field leaves emptied and unknown fields stay`() throws {
        let parents = #""spaceId":"\#(space.uuidString)","parentId":"\#(profile.uuidString)""#
        let received = try object(#"{"name":"Projets","order":1,"isCollapsed":false,"icon":"star","future":1,"# + parents + "}")
        let mine = SyncFields.folder(SyncFolderFields(name: "Projets", order: 1, isCollapsed: false, spaceId: space))
        let sent = SyncFieldMerge.merged(remote: received, local: mine.json, baseline: nil, knownKeys: SyncRecordType.folder.fieldKeys)
        #expect(sent.objectValue["parentId"] == nil)
        #expect(sent.objectValue["icon"] == nil)
        #expect(sent.objectValue["future"] == .number(1))
        #expect(SyncFields(json: sent, type: .folder) == mine)
    }

    /// Review SY1: `SyncRecordType.fieldKeys` lists exactly the fields each type encodes.
    @Test func `the known fields of each type are the ones it encodes`() throws {
        let theme = try #require(SpaceTheme.presets.first)
        let source = SyncExtensionSource.package(blobID: UUID(), blobKey: "k", sha256: "s", size: 1, fileName: "x.zip")
        let tab = try SyncDeviceTabsFields.Tab(url: #require(URL(string: "https://example.com")), title: "Exemple")
        let samples: [SyncFields] = [
            .profile(SyncProfileFields(name: "P", order: 1)),
            .space(SyncSpaceFields(name: "S", symbol: "star", theme: theme, order: 1, profileId: profile)),
            .folder(SyncFolderFields(
                name: "F", order: 1, isCollapsed: true, spaceId: space, parentId: profile, icon: "star", textColor: "#000000",
                backgroundColor: "#FFFFFF",
            )),
            .tab(SyncTabFields(
                place: .pinned, url: URL(string: "https://example.com"), title: "T", order: 1, profileId: profile,
                spaceId: space, folderId: profile,
            )),
            .webExtension(SyncExtensionFields(
                identifier: "x", name: "X", version: "1", source: source, isEnabled: true, allowsPrivateWindows: true,
                showsButton: true, grantedPermissions: ["tabs": nil], deniedPermissions: ["storage": nil],
                grantedMatchPatterns: ["*://*/*": nil], deniedMatchPatterns: ["https://a/*": nil],
            )),
            .setting(SyncSettingFields(key: "showsHomeButton", value: .bool(true))),
            .sitePermission(SyncSitePermissionFields(origin: "https://example.com", kind: "camera", decision: "deny", profileId: profile)),
            .siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.25)),
            .deviceTabs(SyncDeviceTabsFields(deviceId: profile, name: "Mac", spaces: [.init(spaceId: space, name: "S", tabs: [tab])])),
        ]
        #expect(Set(samples.map(\.type)) == Set(SyncRecordType.allCases))
        for sample in samples {
            #expect(Set(sample.json.objectValue.keys) == sample.type.fieldKeys, "\(sample.type)")
        }
    }

    /// Review SY28: fields that can't be encoded are never sent as empty fields, nor taken for a deletion.
    @Test func `fields that can't be encoded are left aside`() {
        let zoom = SyncFields.siteZoom(SyncSiteZoomFields(site: "example.com", level: .nan))
        #expect(zoom.encodedJSON == nil)
        var detector = SyncChangeDetector()
        let id = UUID()
        var state = SyncState()
        state.entries[id] = SyncEntry(type: "siteZoom", version: 1, local: .object(["site": .string("example.com"), "level": .number(1)]))
        #expect(detector.changes(in: [id: zoom], state: state, now: .now).changes.isEmpty)
    }

    @Test func `settings are read as UserDefaults keeps them`() {
        #expect(SyncedSettings.value(true as NSNumber, for: "showsHomeButton") == .bool(true))
        #expect(SyncedSettings.value("NO", for: "confirmBeforeQuitting") == .bool(false))
        #expect(SyncedSettings.value(1 as NSNumber, for: "showsHomeButton") == nil)
        #expect(SyncedSettings.value(30 as NSNumber, for: "tabSuspensionDelay") == .number(30))
        #expect(SyncedSettings.value("0", for: "tabSuspensionDelay") == .number(0))
        #expect(SyncedSettings.value("bing", for: "searchEngine") == .string("bing"))
        #expect(SyncedSettings.value("bing", for: "sidebarWidth") == nil)
        #expect(SyncedSettings.value("duckDuckGo", for: "searchSuggestionSource") == .string("duckDuckGo"))
        #expect(SyncedSettings.value("yahoo", for: "searchSuggestionSource") == nil)
        #expect(SyncedSettings.defaultsValue(of: .number(60)) as? Int == 60)
        #expect(SyncedSettings.keys.contains("homePage"))
        #expect(!SyncedSettings.keys.contains("blocksAdsAndTrackers"))
    }
}
