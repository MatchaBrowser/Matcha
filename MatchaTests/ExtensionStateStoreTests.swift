import Foundation
@testable import Matcha
import Testing

@MainActor
struct ExtensionStateStoreTests {
    private func defaults() throws -> UserDefaults {
        let name = "ExtensionStateStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func `states survive a new store on the same defaults`() throws {
        let defaults = try defaults()
        var state = ExtensionState()
        state.grantedPermissions = ["tabs": .distantFuture]
        state.grantedMatchPatterns = ["*://*.example.com/*": .distantFuture]
        state.deniedPermissions = ["cookies": .distantFuture]
        state.hasAccessToPrivateData = true
        ExtensionStateStore(defaults: defaults).setState(state, for: "abc")

        let reopened = ExtensionStateStore(defaults: defaults)
        #expect(reopened.state(for: "abc") == state)
        #expect(reopened.identifiers == ["abc"])
        reopened.removeState(for: "abc")
        #expect(ExtensionStateStore(defaults: defaults).state(for: "abc") == nil)
    }

    @Test func `without defaults nothing is written but states are kept in memory`() {
        let store = ExtensionStateStore(defaults: nil)
        var state = ExtensionState()
        state.isEnabled = false
        store.setState(state, for: "abc")
        #expect(store.state(for: "abc")?.isEnabled == false)
    }

    @Test func `an unreadable saved value is ignored`() throws {
        let defaults = try defaults()
        defaults.set(Data("pas du JSON".utf8), forKey: ExtensionStateStore.defaultsKey)
        #expect(ExtensionStateStore(defaults: defaults).identifiers.isEmpty)
    }

    @Test func `private windows are refused by default`() {
        #expect(!ExtensionState().hasAccessToPrivateData)
        #expect(ExtensionState().isEnabled)
    }

    @Test func `expired decisions are dropped`() {
        let now = Date(timeIntervalSince1970: 1000)
        var state = ExtensionState()
        state.grantedPermissions = ["tabs": now.addingTimeInterval(-1), "cookies": now.addingTimeInterval(60)]
        state.deniedMatchPatterns = ["*://a.test/*": now]
        let kept = state.removingExpired(at: now)
        #expect(kept.grantedPermissions == ["cookies": now.addingTimeInterval(60)])
        #expect(kept.deniedMatchPatterns.isEmpty)
    }

    // MARK: Dossier des extensions

    @Test func `identifiers are lowercase host labels`() {
        #expect(ExtensionInstallDirectory.isValidIdentifier("abc-123"))
        #expect(ExtensionInstallDirectory.isValidIdentifier("0f2c9a7e-5b1d-4c3e-9a8b-112233445566"))
        #expect(!ExtensionInstallDirectory.isValidIdentifier(""))
        #expect(!ExtensionInstallDirectory.isValidIdentifier("uBlock"))
        #expect(!ExtensionInstallDirectory.isValidIdentifier("a b"))
        #expect(!ExtensionInstallDirectory.isValidIdentifier("-abc"))
        #expect(!ExtensionInstallDirectory.isValidIdentifier("abc-"))
        #expect(!ExtensionInstallDirectory.isValidIdentifier("é"))
        #expect(!ExtensionInstallDirectory.isValidIdentifier(String(repeating: "a", count: 64)))
    }

    @Test func `installed extensions are the valid folders with a manifest`() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("Extensions-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: directory) }
        for name in ["zeta", "alpha", "Invalid", "no-manifest", ".hidden"] {
            try manager.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: true)
            if name != "no-manifest" {
                try Data("{}".utf8).write(to: directory.appendingPathComponent(name).appendingPathComponent("manifest.json"))
            }
        }
        try Data().write(to: directory.appendingPathComponent("file"))

        let found = ExtensionInstallDirectory.installedExtensions(in: directory)
        #expect(found.map(\.identifier) == ["alpha", "zeta"])
        #expect(found.first?.url.lastPathComponent == "alpha")
        #expect(ExtensionInstallDirectory.installedExtensions(in: directory.appendingPathComponent("absent")).isEmpty)
    }

    // MARK: Demandes

    @Test func `requests are sorted and deduplicated`() {
        let permissions = ExtensionPermissionRequest(extensionName: "Ext", permissions: ["tabs", "cookies", "tabs"])
        #expect(permissions.permissions == ["cookies", "tabs"])
        #expect(!permissions.isEmpty)

        let addresses = ["https://b.example/x", "https://a.example/y", "https://a.example/z"].compactMap(URL.init(string:))
        let urls = ExtensionPermissionRequest(extensionName: "Ext", urls: addresses)
        #expect(urls.websites == ["a.example", "b.example"])

        let all = ExtensionPermissionRequest(extensionName: "Ext", matchPatterns: ["<all_urls>"], includesAllWebsites: true)
        #expect(all.allWebsites)
        #expect(ExtensionPermissionRequest(extensionName: "Ext", permissions: []).isEmpty)
    }

    @Test func `alert details list permissions then websites`() {
        let request = ExtensionPermissionRequest(extensionName: "Ext", permissions: ["tabs"])
        #expect(ExtensionPermissionAlert.details(of: request).contains("tabs"))
        let all = ExtensionPermissionRequest(extensionName: "Ext", matchPatterns: ["*://*/*"], includesAllWebsites: true)
        #expect(!ExtensionPermissionAlert.details(of: all).contains("*://*/*"))
    }
}
