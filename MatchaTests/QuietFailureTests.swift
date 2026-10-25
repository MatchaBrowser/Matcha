import Foundation
@testable import Matcha
import Testing

/// Review TR4: a file that can't be read is told apart from a missing one, and never erased by a failed save.
struct QuietFailureTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "QuietFailureTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    @Test func `a missing sync state is a first sync, an unreadable one isn't`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(SyncStateFile(url: folder.appending(path: "state.json")).load() == .missing)

        // Present but unreadable (here, a folder): the same account, never a first sync.
        let unreadable = folder.appending(path: "folder.json")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        #expect(SyncStateFile(url: unreadable).load() == .unreadable)
        #expect(FileManager.default.fileExists(atPath: unreadable.path))
    }

    @Test func `an undecodable sync configuration gives the default one`() throws {
        let defaults = try #require(UserDefaults(suiteName: "QuietFailureTests-\(UUID().uuidString)"))
        defaults.set(Data("not json".utf8), forKey: SyncConfiguration.defaultsKey)
        #expect(SyncConfiguration.load(from: defaults) == SyncConfiguration())

        var configuration = SyncConfiguration()
        configuration.email = "me@example.com"
        configuration.save(to: defaults)
        #expect(SyncConfiguration.load(from: defaults) == configuration)
    }

    @Test @MainActor func `undecodable synced extensions start empty`() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "extensions.json")
        try Data("not json".utf8).write(to: url)
        #expect(SyncedExtensions(url: url).packages.isEmpty)
        #expect(SyncedExtensions(url: folder.appending(path: "missing.json")).packages.isEmpty)
    }

    /// Review SY11: one extensions file per account, the old single file taken over by the first, deleted at sign-out.
    @Test @MainActor func `synced extensions are kept per account`() {
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = folder.appending(path: "extensions.json")
        let first = folder.appending(path: "extensions-a.json")
        let second = folder.appending(path: "extensions-b.json")
        let old = SyncedExtensions(url: legacy)
        old.ignored = ["com.example.old"]

        let synced = SyncedExtensions(url: nil)
        synced.use(url: first, legacy: legacy)
        #expect(synced.ignored == ["com.example.old"])
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        synced.use(url: second, legacy: legacy)
        #expect(synced.ignored.isEmpty)
        synced.ignored = ["com.example.b"]
        synced.forget()
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: first.path))
    }
}
