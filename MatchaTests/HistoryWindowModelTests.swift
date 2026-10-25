import Foundation
@testable import Matcha
import Testing

/// The history window's sections (review SV10): recomputed for its profile only, later after visits than after a
/// keystroke.
@MainActor
struct HistoryWindowModelTests {
    @Test func `visits wait longer than keystrokes and other profiles don't count`() async throws {
        let store = try HistoryStore(container: BrowserSchema.makeContainer(inMemory: true))
        let profile = UUID()
        let model = HistoryWindowModel(store: store, profileID: profile)
        #expect(model.refreshDelay == .zero)
        await model.refresh()
        let key = model.refreshKey

        try store.recordVisit(url: #require(URL(string: "https://ailleurs.example/")), title: nil, profileID: UUID(), spaceID: nil)
        #expect(model.refreshKey == key)
        try store.recordVisit(url: #require(URL(string: "https://ici.example/")), title: nil, profileID: profile, spaceID: nil)
        #expect(model.refreshKey != key)
        #expect(model.refreshDelay == .milliseconds(300))
        model.searchText = "ici"
        #expect(model.refreshDelay == .milliseconds(100))
    }
}
