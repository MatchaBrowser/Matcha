import Foundation
@testable import Matcha
import Testing
import WebKit

/// Settings > Extensions (review TS12): the installed extensions as the list shows them, what an offer from another Mac
/// allows (add, unavailable, to reinstall), and the message of a failure. Temporary folders, an in-memory server, the
/// test extension of the installation tests.
@MainActor
@Suite(.webKit)
struct ExtensionsSettingsModelTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ExtensionsSettingsModelTests-\(UUID().uuidString)",
        isDirectory: true,
    )
    private let server = InMemorySyncServer()
    /// Of the random form: the only one sync may propose (review EX10).
    private let identifier = "0123456789abcdef0123456789abcdef"

    init() {
        WKWebExtension.MatchPattern.registerCustomURLScheme(TestPages.scheme)
    }

    /// The settings of a Mac, its extension sync talking to the server.
    private func makeModel(_ name: String) -> ExtensionsSettingsModel {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        let manager = ExtensionManager(
            configuration: .nonPersistent(),
            store: ExtensionStateStore(defaults: nil),
            directory: folder.appendingPathComponent("Extensions", isDirectory: true),
        )
        let installer = ExtensionInstaller(manager: manager, stagingRoot: folder.appendingPathComponent("Staging", isDirectory: true))
        let adapter = ExtensionSyncAdapter(manager: manager, synced: SyncedExtensions(url: nil), installer: installer)
        adapter.transport = InMemorySyncTransport(server: server)
        return ExtensionsSettingsModel(manager: manager, syncAdapter: adapter)
    }

    /// Settings of a Mac where the test extension is installed from its file, its package uploaded.
    private func modelWithExtension() async throws -> ExtensionsSettingsModel {
        let model = makeModel("A")
        let file = try #require(Bundle(for: TestPages.self).url(forResource: "test-extension-package.zip", withExtension: nil))
        let installer = model.syncAdapter.installer
        try await installer.install(installer.prepare(fileAt: file, preferredIdentifier: identifier), allowsPrivateWindows: false)
        await model.syncAdapter.preparePackages(using: InMemorySyncTransport(server: server))
        return model
    }

    private func cleanUp(_ models: ExtensionsSettingsModel...) {
        for model in models {
            for identifier in model.manager.contexts.keys {
                model.manager.unload(identifier: identifier)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    @Test func `the list shows an installed extension with its name and version`() async throws {
        let model = try await modelWithExtension()
        defer { cleanUp(model) }
        let installed = try #require(model.installed.first)
        #expect(model.installed.count == 1)
        #expect(installed.id == identifier)
        #expect(installed.name == model.manager.installed[identifier]?.displayName)
        #expect(installed.version == model.manager.installed[identifier]?.version)
        #expect(installed.appName == nil)
        #expect(installed.isEnabled)
        #expect(!installed.isMissing)
    }

    @Test func `an offer from another Mac can be added, then is to reinstall when its package stays missing`() async throws {
        let first = try await modelWithExtension()
        let second = makeModel("B")
        defer { cleanUp(first, second) }
        let fields = try #require(first.syncAdapter.fields()[identifier])
        second.syncAdapter.apply(fields)
        let offer = try #require(second.offers.first)
        #expect(second.offers.count == 1)
        #expect(!second.isUpdate(offer))
        #expect(second.availability(of: offer) == .ready)

        let package = try #require(first.syncAdapter.synced.packages[identifier])
        await server.deleteBlob(id: package.blobID)
        for _ in 1 ... ExtensionSyncAdapter.maximumMissingAttempts {
            _ = try? await second.syncAdapter.prepareOffer(offer)
        }
        #expect(second.availability(of: offer) == .packageLost)

        // Without a server that keeps packages: unavailable.
        second.syncAdapter.transport = nil
        #expect(second.availability(of: offer) == .packageUnavailable)

        second.ignoreOffer(offer)
        #expect(second.offers.isEmpty)
    }

    @Test func `a failure is shown in words, and the work ends`() async {
        let model = makeModel("A")
        defer { cleanUp(model) }
        await model.prepare { _ in throw SyncTransportError.blobNotFound }
        #expect(model.errorMessage == ExtensionInstallError.packageNotOnServer.localizedDescription)
        #expect(!model.isWorking)
        #expect(model.candidate == nil)
    }
}
