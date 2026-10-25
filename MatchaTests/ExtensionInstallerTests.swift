import Foundation
@testable import Matcha
import Testing
import WebKit

/// Extension installation (task 6.4): from a file or a folder, from an app's Safari extension; permissions granted
/// at installation, update, uninstallation. Temporary folders only, nothing in the user's folders.
@MainActor
@Suite(.webKit)
struct ExtensionInstallerTests {
    private let root: URL
    private let directory: URL
    private let store = ExtensionStateStore(defaults: nil)
    private let manager: ExtensionManager
    private let installer: ExtensionInstaller

    init() throws {
        // The `obtest://*/*` patterns of the test manifest can only be read once the scheme is declared.
        WKWebExtension.MatchPattern.registerCustomURLScheme(TestPages.scheme)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExtensionInstallerTests-\(UUID().uuidString)",
            isDirectory: true,
        )
        directory = root.appendingPathComponent("Extensions", isDirectory: true)
        manager = ExtensionManager(configuration: .nonPersistent(), store: store, directory: directory)
        installer = ExtensionInstaller(manager: manager, stagingRoot: root.appendingPathComponent("Staging", isDirectory: true))
    }

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle(for: TestPages.self).url(forResource: name, withExtension: nil))
    }

    private func cleanUp() {
        for identifier in manager.contexts.keys {
            manager.unload(identifier: identifier)
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func stagingIsEmpty() -> Bool {
        let staging = root.appendingPathComponent("Staging")
        return ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty
    }

    @Test func `a zip file is installed in the extensions folder, its permissions granted`() async throws {
        defer { cleanUp() }
        let candidate = try await installer.prepare(fileAt: fixture("test-extension-package.zip"))
        let identifier = candidate.identifier
        // Random, never derived from the name (audit E1).
        #expect(identifier.count == 32 && ExtensionInstallDirectory.isValidIdentifier(identifier))
        #expect(candidate.mode == .new)
        #expect(candidate.publisher == nil)
        #expect(candidate.summary == [.browsingHistory, .allWebsites])

        try await installer.install(candidate, allowsPrivateWindows: false)

        let folder = directory.appendingPathComponent(identifier)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path))
        let context = try #require(manager.contexts[identifier])
        #expect(context.isLoaded)
        #expect(context.permissionStatus(for: .tabs) == .grantedExplicitly)
        #expect(!context.hasAccessToPrivateData)
        let state = try #require(store.state(for: identifier))
        #expect(state.grantedPermissions["tabs"] != nil)
        #expect(state.grantedMatchPatterns["obtest://*/*"] != nil)
        #expect(state.appExtensionPath == nil)
        #expect(state.version == candidate.webExtension.version)
        #expect(manager.installedIdentifiers == [identifier])
        #expect(stagingIsEmpty())
    }

    /// Audit E1: a file with an installed extension's name, from an unproven developer, never gets its data.
    @Test func `an unverified file with the name of an installed extension replaces it and erases its data`() async throws {
        defer { cleanUp() }
        let first = try await installer.prepare(fileAt: fixture("test-extension-package.crx"))
        try await installer.install(first, allowsPrivateWindows: true)
        #expect(manager.contexts[first.identifier]?.hasAccessToPrivateData == true)

        let second = try await installer.prepare(fileAt: fixture("test-extension-package.xpi"))
        #expect(second.identifier != first.identifier)
        #expect(second.mode == .replacement(identifier: first.identifier, previousVersion: first.webExtension.version))
        try await installer.install(second, allowsPrivateWindows: false)

        #expect(manager.installedIdentifiers == [second.identifier])
        #expect(store.state(for: first.identifier) == nil)
        #expect(manager.contexts[second.identifier]?.isLoaded == true)
        #expect(manager.contexts[second.identifier]?.hasAccessToPrivateData == false)
    }

    /// Audit E1 and E2: the same verified developer updates in place, keeping data and the user's refusals.
    @Test func `a crx signed by the same developer updates in place and keeps the user's refusals`() async throws {
        defer { cleanUp() }
        let archive = try Data(contentsOf: fixture("test-extension-package.zip"))
        let developer = try CRXBuilder.Developer()
        let signed = root.appendingPathComponent("signe.crx")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try CRXBuilder.crx(archive: archive, developer: developer).write(to: signed)
        let first = try await installer.prepare(fileAt: signed)
        #expect(first.publisher == developer.identifier)
        try await installer.install(first, allowsPrivateWindows: true)
        // The user then refuses the tabs permission (WebKit's decision, saved by the manager).
        let context = try #require(manager.contexts[first.identifier])
        context.setPermissionStatus(.deniedExplicitly, for: .tabs)
        try await waitUntil { store.state(for: first.identifier)?.deniedPermissions["tabs"] != nil }

        let update = try await installer.prepare(fileAt: signed)
        #expect(update.identifier == first.identifier)
        #expect(update.mode == .update(previousVersion: first.webExtension.version))
        #expect(update.addedSummary.isEmpty)
        #expect(update.allowedPrivateWindows)
        try await installer.install(update, allowsPrivateWindows: true)
        let updated = try #require(store.state(for: first.identifier))
        #expect(updated.deniedPermissions["tabs"] != nil)
        #expect(updated.grantedPermissions["tabs"] == nil)
        #expect(updated.publisher == developer.identifier)

        // Another developer's file with the same name: a replacement, not an update.
        let impostor = root.appendingPathComponent("faux.crx")
        try CRXBuilder.crx(archive: archive, developer: CRXBuilder.Developer()).write(to: impostor)
        let fake = try await installer.prepare(fileAt: impostor)
        #expect(fake.identifier != first.identifier)
        #expect(fake.mode == .replacement(identifier: first.identifier, previousVersion: first.webExtension.version))
        installer.discard(fake)
    }

    /// Review EX2: the package of an extension installed here, offered by another Mac, keeps its identifier and data.
    @Test func `an offer for an installed extension updates it in place, even unsigned`() async throws {
        defer { cleanUp() }
        let first = try await installer.prepare(fileAt: fixture("test-extension-package.crx"))
        try await installer.install(first, allowsPrivateWindows: true)

        let offer = try await installer.prepare(fileAt: fixture("test-extension-package.xpi"), preferredIdentifier: first.identifier)
        #expect(offer.identifier == first.identifier)
        #expect(offer.mode == .update(previousVersion: first.webExtension.version))
        #expect(offer.allowedPrivateWindows)
        try await installer.install(offer, allowsPrivateWindows: true)
        #expect(manager.installedIdentifiers == [first.identifier])
        #expect(manager.contexts[first.identifier]?.isLoaded == true)
        #expect(store.state(for: first.identifier)?.hasAccessToPrivateData == true)
    }

    /// Review EX20 (TS9): an update whose files can't be put in place leaves the installed version loaded.
    @Test func `an update that can't be put in place keeps the installed version`() async throws {
        defer { cleanUp() }
        let first = try await installer.prepare(fileAt: fixture("test-extension-package.crx"))
        try await installer.install(first, allowsPrivateWindows: false)
        let update = try await installer.prepare(fileAt: fixture("test-extension-package.xpi"), preferredIdentifier: first.identifier)
        // The extensions folder can't change: the files can't be put in place.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        await #expect(throws: (any Error).self) { try await installer.install(update, allowsPrivateWindows: false) }
        #expect(manager.contexts[first.identifier]?.isLoaded == true)
        #expect(manager.installedIdentifiers == [first.identifier])
    }

    /// Review EX2: an offered `.crx` signed by another publisher than the installed extension's still replaces it.
    @Test func `an offer signed by another publisher replaces the installed extension`() async throws {
        defer { cleanUp() }
        let archive = try Data(contentsOf: fixture("test-extension-package.zip"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let signed = root.appendingPathComponent("signed.crx")
        try CRXBuilder.crx(archive: archive, developer: CRXBuilder.Developer()).write(to: signed)
        let first = try await installer.prepare(fileAt: signed)
        try await installer.install(first, allowsPrivateWindows: false)

        let impostor = root.appendingPathComponent("impostor.crx")
        try CRXBuilder.crx(archive: archive, developer: CRXBuilder.Developer()).write(to: impostor)
        let offer = try await installer.prepare(fileAt: impostor, preferredIdentifier: first.identifier)
        #expect(offer.identifier != first.identifier)
        #expect(offer.mode == .replacement(identifier: first.identifier, previousVersion: first.webExtension.version))
        installer.discard(offer)
    }

    @Test func `an unpacked folder is copied, the original stays`() async throws {
        defer { cleanUp() }
        let source = try TestExtension.makeFolder(in: root)
        let candidate = try await installer.prepare(fileAt: source)
        try await installer.install(candidate, allowsPrivateWindows: false)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("manifest.json").path))
        #expect(manager.contexts[candidate.identifier] != nil)
    }

    @Test func `refused files leave nothing behind`() async throws {
        defer { cleanUp() }
        await #expect(throws: ExtensionInstallError.unreadable) {
            try await installer.prepare(fileAt: fixture("test-zip-traversal.zip"))
        }
        await #expect(throws: ExtensionInstallError.unknownFormat) {
            try await installer.prepare(fileAt: fixture("test-extension-content.js"))
        }
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await #expect(throws: ExtensionInstallError.noManifest) {
            try await installer.prepare(fileAt: empty)
        }
        #expect(stagingIsEmpty())
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("evil.txt").path))
        #expect(manager.installedIdentifiers.isEmpty)
    }

    @Test func `a cancelled candidate is discarded`() async throws {
        defer { cleanUp() }
        let candidate = try await installer.prepare(fileAt: fixture("test-extension-package.zip"))
        #expect(!stagingIsEmpty())
        installer.discard(candidate)
        // Deleted off the main thread (review EX19).
        try await waitUntil { stagingIsEmpty() }
        #expect(manager.installedIdentifiers.isEmpty)
    }

    @Test func `uninstalling removes the folder, the state and the extension`() async throws {
        defer { cleanUp() }
        let candidate = try await installer.prepare(fileAt: fixture("test-extension-package.zip"))
        try await installer.install(candidate, allowsPrivateWindows: false)

        await manager.uninstall(identifier: candidate.identifier)

        #expect(manager.contexts[candidate.identifier] == nil)
        #expect(manager.installed[candidate.identifier] == nil)
        #expect(store.state(for: candidate.identifier) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate.identifier).path))
    }

    // MARK: Safari extension of an app

    /// Fake `.appex`: the test extension in `Contents/Resources`.
    private func makeAppExtension() throws -> SafariAppExtension {
        let app = root.appendingPathComponent("Test.app", isDirectory: true)
        let appex = app.appendingPathComponent("Contents/PlugIns/Extension.appex", isDirectory: true)
        let contents = appex.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        _ = try TestExtension.makeFolder(in: contents, named: "Resources")
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.test.extension",
            "CFBundlePackageType": "XPC!",
            "NSExtension": ["NSExtensionPointIdentifier": SafariExtensionFinder.extensionPoint],
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(SafariExtensionFinder.extensions(of: app, checksSignatures: false).first)
    }

    /// Audit E7: a bundle found later at the same place with another signed identity isn't loaded.
    @Test func `a safari extension whose identity changed isn't loaded`() async throws {
        defer { cleanUp() }
        let appExtension = try makeAppExtension()
        var state = ExtensionState()
        state.appExtensionPath = appExtension.extensionURL.path
        state.appExtensionIdentity = "com.example.other.extension (ABCDE12345)"
        store.setState(state, for: "safari-test")
        await #expect(throws: ExtensionError.identityChanged("safari-test")) {
            try await manager.read("safari-test")
        }
    }

    @Test func `an unsigned safari extension is refused by WebKit`() async throws {
        defer { cleanUp() }
        let appExtension = try makeAppExtension()
        #expect(appExtension.displayName == "Matcha Test Extension")
        // WebKit checks the manifest against the signature of the `.appex`: a modified or unsigned app extension does
        // not load.
        await #expect {
            try await installer.prepare(appExtension)
        } throws: { error in
            if case .invalidManifest = error as? ExtensionInstallError {
                return true
            }
            return false
        }
        #expect(manager.installedIdentifiers.isEmpty)
    }

    @Test func `a safari extension whose app was deleted stays listed until removed`() async throws {
        defer { cleanUp() }
        var state = ExtensionState()
        state.appExtensionPath = root.appendingPathComponent("Deleted.app/Contents/PlugIns/Extension.appex").path
        store.setState(state, for: "safari-com-example-deleted")
        #expect(manager.installedIdentifiers == ["safari-com-example-deleted"])
        #expect(manager.webExtensionIdentifier(for: "safari-com-example-deleted") == "safari-com-example-deleted")

        manager.start()
        await #expect(throws: ExtensionError.notInstalled("safari-com-example-deleted")) {
            try await manager.read("safari-com-example-deleted")
        }
        #expect(manager.contexts.isEmpty)

        await manager.uninstall(identifier: "safari-com-example-deleted")
        #expect(manager.installedIdentifiers.isEmpty)
    }

    @Test func `safari identifiers carry the signing team, like in Safari`() throws {
        // The tests' host app is signed; without a team (ad hoc signature), the bundle identifier alone.
        let app = Bundle.main.bundleURL
        let bundleIdentifier = try #require(Bundle.main.bundleIdentifier)
        let identifier = try #require(SafariExtensionFinder.safariIdentifier(ofAppExtensionAt: app))
        if let team = SafariExtensionFinder.teamIdentifier(ofBundleAt: app) {
            #expect(identifier == "\(bundleIdentifier) (\(team))")
        } else {
            #expect(identifier == bundleIdentifier)
        }
        #expect(SafariExtensionFinder.safariIdentifier(ofAppExtensionAt: root.appendingPathComponent("Missing.appex")) == nil)
    }
}
