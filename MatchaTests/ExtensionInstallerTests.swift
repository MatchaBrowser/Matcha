import Foundation
@testable import Matcha
import Testing
import WebKit

/// Extension installation (task 6.4): from a file or a folder, from an app's Safari extension; permissions granted
/// at installation, update, uninstallation. Temporary folders only, nothing in the user's folders.
@MainActor
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
        #expect(candidate.identifier == "matcha-test-extension")
        #expect(!candidate.isUpdate)
        #expect(candidate.summary == [.browsingHistory, .allWebsites])

        try await installer.install(candidate, allowsPrivateWindows: false)

        let folder = directory.appendingPathComponent("matcha-test-extension")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path))
        let context = try #require(manager.contexts["matcha-test-extension"])
        #expect(context.isLoaded)
        #expect(context.permissionStatus(for: .tabs) == .grantedExplicitly)
        #expect(!context.hasAccessToPrivateData)
        let state = try #require(store.state(for: "matcha-test-extension"))
        #expect(state.grantedPermissions["tabs"] != nil)
        #expect(state.grantedMatchPatterns["obtest://*/*"] != nil)
        #expect(state.appExtensionPath == nil)
        #expect(manager.installedIdentifiers == ["matcha-test-extension"])
        #expect(stagingIsEmpty())
    }

    @Test func `crx and xpi files give the same extension, installed again as an update`() async throws {
        defer { cleanUp() }
        let first = try await installer.prepare(fileAt: fixture("test-extension-package.crx"))
        try await installer.install(first, allowsPrivateWindows: true)
        #expect(manager.contexts[first.identifier]?.hasAccessToPrivateData == true)

        let second = try await installer.prepare(fileAt: fixture("test-extension-package.xpi"))
        #expect(second.identifier == first.identifier)
        #expect(second.isUpdate)
        try await installer.install(second, allowsPrivateWindows: false)

        #expect(manager.installedIdentifiers == [first.identifier])
        #expect(manager.contexts[first.identifier]?.isLoaded == true)
        #expect(manager.contexts[first.identifier]?.hasAccessToPrivateData == false)
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
        #expect(stagingIsEmpty())
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
        return try #require(SafariExtensionFinder.extensions(of: app).first)
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
