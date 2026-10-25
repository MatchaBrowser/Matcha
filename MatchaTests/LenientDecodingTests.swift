import Foundation
@testable import Matcha
import Testing

/// Saved values read leniently (audit R4): a field added later or one unreadable entry no longer loses everything.
@MainActor
struct LenientDecodingTests {
    private let suiteName = "LenientDecodingTests-\(UUID().uuidString)"

    @Test func `an extension state saved by an older version keeps its decisions`() throws {
        let json = #"{"isEnabled": false, "grantedPermissions": {"tabs": 0}}"#
        let state = try JSONDecoder().decode(ExtensionState.self, from: Data(json.utf8))
        #expect(!state.isEnabled)
        #expect(state.grantedPermissions["tabs"] == Date(timeIntervalSinceReferenceDate: 0))
        #expect(state.grantedMatchPatterns.isEmpty)
        #expect(!state.hasAccessToPrivateData)
        #expect(state.showsButton == nil)
    }

    @Test func `one unreadable extension state is dropped alone and the saved value is kept aside`() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let json = #"{"bon": {"isEnabled": false}, "abime": {"isEnabled": "oui"}}"#
        defaults.set(Data(json.utf8), forKey: ExtensionStateStore.defaultsKey)

        let store = ExtensionStateStore(defaults: defaults)
        #expect(store.state(for: "abime") == nil)
        #expect(store.state(for: "bon")?.isEnabled == false)
        #expect(defaults.data(forKey: ExtensionStateStore.unreadableKey) == Data(json.utf8))
    }

    @Test func `an unreadable saved value is kept aside before being written over`() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let garbage = Data("pas du JSON".utf8)
        defaults.set(garbage, forKey: ExtensionStateStore.defaultsKey)

        let store = ExtensionStateStore(defaults: defaults)
        #expect(store.identifiers.isEmpty)
        store.setState(ExtensionState(), for: "nouvelle")
        #expect(defaults.data(forKey: ExtensionStateStore.unreadableKey) == garbage)
    }

    @Test func `one unreadable download is dropped alone`() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let good = SavedDownload(id: UUID(), fileName: "a.zip", fileURL: nil, outcome: .finished, byteCount: 1, failureReason: nil)
        let goodJSON = try #require(try String(bytes: JSONEncoder().encode(good), encoding: .utf8))
        let json = "[\(goodJSON), {\"fileName\": 3}]"
        defaults.set(Data(json.utf8), forKey: SavedDownloadList.defaultsKey)
        #expect(SavedDownloadList.load(from: defaults) == [good])
    }
}
