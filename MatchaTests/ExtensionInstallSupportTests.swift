import Foundation
@testable import Matcha
import Testing

/// Pure types of extension installation (task 6.4): identifiers, permission summary, Safari extensions of apps.
@MainActor
struct ExtensionInstallSupportTests {
    // MARK: Identifiers

    @Test func `slugs are lowercase ASCII with dashes`() {
        #expect(ExtensionIdentifier.slug("Dark Reader") == "dark-reader")
        #expect(ExtensionIdentifier.slug("Proton Pass: Password Manager") == "proton-pass-password-manager")
        #expect(ExtensionIdentifier.slug("  Éclair d'été !  ") == "eclair-d-ete")
        #expect(ExtensionIdentifier.slug("uBlock Origin Lite") == "ublock-origin-lite")
        #expect(ExtensionIdentifier.slug("日本語") == nil)
        let long = ExtensionIdentifier.slug(String(repeating: "abc ", count: 30))
        #expect(long.map { $0.count <= 63 && !$0.hasSuffix("-") } == true)
    }

    @Test func `names come from the default locale`() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Manifest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("_locales/fr"), withIntermediateDirectories: true)
        let manifest = #"{"manifest_version": 3, "name": "__MSG_ExtName__", "version": "1", "default_locale": "fr"}"#
        try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        let messages = #"{"extName": {"message": "Lecteur Sombre"}}"#
        try Data(messages.utf8).write(to: folder.appendingPathComponent("_locales/fr/messages.json"))
        #expect(ExtensionManifestFile(folder: folder)?.name == "Lecteur Sombre")
    }

    /// Audit E1: never the name, never a Safari extension's prefix, never twice the same.
    @Test func `package identifiers are random`() {
        let first = ExtensionIdentifier.random()
        #expect(ExtensionInstallDirectory.isValidIdentifier(first))
        #expect(!first.hasPrefix("safari-"))
        #expect(first != ExtensionIdentifier.random())
    }

    /// Audit E2: an update grants what is new, keeps refusals and drops what is no longer asked for.
    @Test func `an update keeps refusals and drops what is no longer asked for`() {
        var state = ExtensionState()
        state.grantedPermissions = ["tabs": .distantFuture, "cookies": .distantFuture, "storage": .distantFuture]
        state.deniedMatchPatterns = ["<all_urls>": .distantFuture]
        state.deniedPermissions = ["history": .distantPast]
        state.applyRequests(
            permissions: ["tabs", "history", "downloads"],
            patterns: ["<all_urls>", "*://example.com/*"],
            optionalPermissions: ["storage"],
        )
        #expect(Set(state.grantedPermissions.keys) == ["tabs", "storage", "history", "downloads"])
        #expect(state.grantedMatchPatterns.keys.sorted() == ["*://example.com/*"])
        #expect(state.deniedMatchPatterns["<all_urls>"] != nil)
        // An expired refusal no longer counts.
        #expect(state.deniedPermissions.isEmpty)
    }

    @Test func `app extension identifiers keep the bundle identifier`() {
        #expect(ExtensionIdentifier.forAppExtension(bundleIdentifier: "me.proton.pass.catalyst.safari-extension")
            == "safari-me-proton-pass-catalyst-safari-extension")
    }

    // MARK: Permission summary

    @Test func `sensitive permissions only, once each, websites last`() {
        let lines = ExtensionPermissionSummary.lines(
            permissions: ["storage", "alarms", "tabs", "webNavigation", "nativeMessaging", "clipboardWrite"],
            hosts: ["*.example.com", "example.com", "proton.me"],
        )
        #expect(lines == [.browsingHistory, .clipboardWrite, .nativeApps, .websites(["example.com", "proton.me"])])
    }

    @Test func `a pattern for every host means all websites`() {
        #expect(ExtensionPermissionSummary.lines(permissions: [], hosts: ["proton.me", nil]) == [.allWebsites])
        #expect(ExtensionPermissionSummary.lines(permissions: ["storage"], hosts: ["*"]) == [.allWebsites])
        #expect(ExtensionPermissionSummary.lines(permissions: ["storage", "scripting"], hosts: []).isEmpty)
    }

    /// Audit E7: local files are named, never as an empty website; `webRequest` sees the pages visited.
    @Test func `local files and web requests are named`() {
        #expect(ExtensionPermissionSummary.lines(permissions: [], hosts: [""], readsLocalFiles: true) == [.localFiles])
        #expect(ExtensionPermissionSummary.lines(permissions: ["webRequest"], hosts: [nil], readsLocalFiles: true) == [
            .browsingHistory, .allWebsites, .localFiles,
        ])
    }

    // MARK: Safari extensions of apps

    /// Creates `name.app` with an extension at the extension point `point` (and its manifest if `hasManifest`).
    private func makeApp(
        in folder: URL,
        name: String,
        extensionIdentifier: String,
        point: String = SafariExtensionFinder.extensionPoint,
        hasManifest: Bool = true,
    ) throws {
        let app = folder.appendingPathComponent("\(name).app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": name], format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))
        let appex = app.appendingPathComponent("PlugIns/Extension.appex/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: appex.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": extensionIdentifier,
            "CFBundleDisplayName": "Safari Extension",
            "NSExtension": ["NSExtensionPointIdentifier": point],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: appex.appendingPathComponent("Info.plist"))
        if hasManifest {
            let manifest = #"{"manifest_version": 3, "name": "\#(name) Extension", "version": "1.0"}"#
            try Data(manifest.utf8).write(to: appex.appendingPathComponent("Resources/manifest.json"))
        }
    }

    @Test func `safari extensions of apps are found, with their manifest name`() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Apps-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try makeApp(in: folder, name: "Zeta", extensionIdentifier: "com.example.zeta.extension")
        try makeApp(in: folder.appendingPathComponent("Utilities"), name: "Alpha", extensionIdentifier: "com.example.alpha.extension")
        try makeApp(in: folder, name: "Widget", extensionIdentifier: "com.example.widget", point: "com.apple.widgetkit-extension")
        try makeApp(in: folder, name: "Broken", extensionIdentifier: "com.example.broken", hasManifest: false)
        // Same extension in a second apps folder: listed only once.
        let other = folder.appendingPathComponent("Other", isDirectory: true)
        try makeApp(in: other, name: "Zeta", extensionIdentifier: "com.example.zeta.extension")

        let found = SafariExtensionFinder.find(in: [folder, other], checksSignatures: false)

        #expect(found.map(\.displayName) == ["Alpha Extension", "Zeta Extension"])
        #expect(found.map(\.appName) == ["Alpha", "Zeta"])
        #expect(found.first?.extensionURL.lastPathComponent == "Extension.appex")
    }
}
