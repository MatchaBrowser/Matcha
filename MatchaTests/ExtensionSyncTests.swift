import Foundation
@testable import Matcha
import Testing
import WebKit

/// Synced extensions (task 7.4, `SYNC.md` § 2.5): two simulated Macs (temporary folders), an in-memory server, the
/// test extension of the installation tests.
@MainActor
struct ExtensionSyncTests {
    private let root: URL
    private let server = InMemorySyncServer()
    private let identifier = "matcha-test-extension"

    /// A Mac: its extension manager, its installer, its extension sync.
    @MainActor
    private struct Mac {
        let manager: ExtensionManager
        let installer: ExtensionInstaller
        let adapter: ExtensionSyncAdapter

        var synced: SyncedExtensions {
            adapter.synced
        }
    }

    init() {
        WKWebExtension.MatchPattern.registerCustomURLScheme(TestPages.scheme)
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ExtensionSyncTests-\(UUID().uuidString)", isDirectory: true)
    }

    private var transport: InMemorySyncTransport {
        InMemorySyncTransport(server: server)
    }

    private func makeMac(_ name: String) -> Mac {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        let manager = ExtensionManager(
            configuration: .nonPersistent(),
            store: ExtensionStateStore(defaults: nil),
            directory: folder.appendingPathComponent("Extensions", isDirectory: true),
        )
        let installer = ExtensionInstaller(manager: manager, stagingRoot: folder.appendingPathComponent("Staging", isDirectory: true))
        let adapter = ExtensionSyncAdapter(manager: manager, synced: SyncedExtensions(url: nil), installer: installer)
        adapter.transport = transport
        return Mac(manager: manager, installer: installer, adapter: adapter)
    }

    /// A Mac where the test extension is installed from its file, and its package uploaded.
    private func macWithExtension() async throws -> Mac {
        let mac = makeMac("A")
        let file = try #require(Bundle(for: TestPages.self).url(forResource: "test-extension-package.zip", withExtension: nil))
        // Its identifier on all the Macs, as sync gives it (`preferredIdentifier`).
        try await mac.installer.install(mac.installer.prepare(fileAt: file, preferredIdentifier: identifier), allowsPrivateWindows: false)
        await mac.adapter.preparePackages(using: transport)
        return mac
    }

    private func cleanUp(_ macs: Mac...) {
        for mac in macs {
            for identifier in mac.manager.contexts.keys {
                mac.manager.unload(identifier: identifier)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    @Test func `an extension installed from a file travels with its package`() async throws {
        let mac = try await macWithExtension()
        defer { cleanUp(mac) }
        let fields = try #require(mac.adapter.fields()[identifier])
        #expect(fields.source.kind == .package)
        let package = try #require(mac.synced.packages[identifier])
        #expect(fields.source.blobId == package.blobID)
        #expect(await server.blobs.keys.contains(package.blobID))

        let file = try await mac.adapter.downloadPackage(package, using: transport)
        let archive = try ZipArchive(data: Data(contentsOf: file))
        let manifest = try #require(archive.entries.first { $0.path == "manifest.json" })
        let installed = try #require(mac.manager.directory?.appendingPathComponent("\(identifier)/manifest.json"))
        #expect(try archive.contents(of: manifest) == Data(contentsOf: installed))

        // Same version: nothing is sent again.
        await mac.adapter.preparePackages(using: transport)
        #expect(await server.blobs.count == 1)
    }

    @Test func `received settings apply to an installed extension`() async throws {
        let mac = try await macWithExtension()
        defer { cleanUp(mac) }
        var fields = try #require(mac.adapter.fields()[identifier])
        fields.isEnabled = false
        fields.showsButton = false
        fields.allowsPrivateWindows = true
        fields.deniedPermissions = ["tabs": nil]
        fields.grantedPermissions["tabs"] = nil
        mac.adapter.apply(fields)

        let state = try #require(mac.manager.store.state(for: identifier))
        #expect(!state.isEnabled)
        #expect(state.showsButton == false)
        // Access to private windows is never granted by sync, and a refusal received applies (SYNC.md § 2.5).
        #expect(!state.hasAccessToPrivateData)
        #expect(state.deniedPermissions["tabs"] == .distantFuture)
        #expect(state.grantedPermissions["tabs"] == nil)
        #expect(mac.synced.offers.isEmpty)
    }

    @Test func `received permissions only reduce those of this Mac`() {
        let now = Date.now
        let (granted, denied) = ExtensionSyncAdapter.reduced(
            granted: ["tabs": now, "storage": now],
            denied: [:],
            receivedGranted: ["tabs": nil, "cookies": nil],
            receivedDenied: ["history": nil],
        )
        // “storage” was withdrawn elsewhere, “cookies” granted elsewhere isn't added here.
        #expect(granted == ["tabs": now])
        #expect(denied == ["history": .distantFuture])
    }

    @Test func `an extension from another Mac waits for the user, who can ignore it`() async throws {
        let first = try await macWithExtension()
        let second = makeMac("B")
        defer { cleanUp(first, second) }
        let fields = try #require(first.adapter.fields()[identifier])
        second.adapter.apply(fields)
        #expect(second.synced.offers[identifier] == fields)
        #expect(second.manager.installedIdentifiers.isEmpty)

        second.adapter.ignore(identifier)
        second.adapter.apply(fields)
        #expect(second.synced.offers.isEmpty)
    }

    @Test func `an offered package installs after review, without being sent again`() async throws {
        let first = try await macWithExtension()
        let second = makeMac("B")
        defer { cleanUp(first, second) }
        let fields = try #require(first.adapter.fields()[identifier])
        second.adapter.apply(fields)

        let candidate = try await second.adapter.prepareOffer(fields)
        #expect(candidate.identifier == identifier)
        try await second.installer.install(candidate, allowsPrivateWindows: false)
        second.adapter.didInstallOffer(fields)
        #expect(second.synced.offers.isEmpty)
        #expect(second.synced.packages[identifier] == first.synced.packages[identifier])

        await second.adapter.preparePackages(using: transport)
        #expect(await server.blobs.count == 1)
    }

    @Test func `a package changed on the server is refused`() async throws {
        let first = try await macWithExtension()
        let second = makeMac("B")
        defer { cleanUp(first, second) }
        let fields = try #require(first.adapter.fields()[identifier])
        let package = try #require(first.synced.packages[identifier])
        await server.replaceBlob(Data(repeating: 1, count: 2048), id: package.blobID)
        await #expect(throws: SyncCryptoError.unreadable) {
            try await second.adapter.prepareOffer(fields)
        }
    }

    @Test func `an extension uninstalled on one Mac goes everywhere, its package with it`() async throws {
        let first = try await macWithExtension()
        let second = makeMac("B")
        defer { cleanUp(first, second) }
        let fields = try #require(first.adapter.fields()[identifier])
        second.adapter.apply(fields)
        try await second.installer.install(second.adapter.prepareOffer(fields), allowsPrivateWindows: false)
        second.adapter.didInstallOffer(fields)

        second.adapter.remove(identifier: identifier)
        for _ in 0 ..< 100 where second.manager.installedIdentifiers.contains(identifier) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(second.manager.installedIdentifiers.isEmpty)

        await first.manager.uninstall(identifier: identifier)
        await first.adapter.deleteObsoletePackages(using: transport)
        #expect(await server.blobs.isEmpty)
        #expect(first.synced.packages.isEmpty)
    }
}
