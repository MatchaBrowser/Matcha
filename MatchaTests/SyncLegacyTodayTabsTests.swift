import Foundation
@testable import Matcha
import Testing

/// Today tabs of the versions before 2026-10-25 (`SYNC.md` § 2.4): forgotten from the state, never deleted.
struct SyncLegacyTodayTabsTests {
    private let space = UUID()
    private let device = UUID()
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func tab(_ place: SyncTabPlace, _ path: String = "") -> SyncFields {
        .tab(SyncTabFields(place: place, url: URL(string: "https://example.com/\(path)"), title: nil, order: 0, spaceId: space))
    }

    private func change(_ fields: SyncFields) -> SyncPendingChange {
        SyncPendingChange(content: SyncContent(fields: fields, modifiedAt: date, modifiedBy: device), local: fields.json)
    }

    @Test func `a today tab is recognized by its type and its place`() {
        #expect(SyncLegacyTodayTabs.isTodayTab(tab(.today).json, type: "tab"))
        #expect(!SyncLegacyTodayTabs.isTodayTab(tab(.pinned).json, type: "tab"))
        #expect(!SyncLegacyTodayTabs.isTodayTab(tab(.today).json, type: "folder"))
        #expect(!SyncLegacyTodayTabs.isTodayTab(nil, type: "tab"))
    }

    @Test func `the state forgets today tabs, nothing else`() {
        let (today, closed, pinnedHere, pinned) = (UUID(), UUID(), UUID(), UUID())
        let legacy = SyncContent(fields: tab(.today), modifiedAt: date, modifiedBy: device)
        var state = SyncState(deviceID: device)
        for id in [today, closed, pinnedHere] {
            state.entries[id] = SyncEntry(type: "tab", version: 1, remote: legacy, local: tab(.today).json)
        }
        state.entries[pinned] = SyncEntry(type: "tab", version: 2, local: tab(.pinned).json)
        state.pending[today] = change(tab(.today, "moved"))
        state.pending[closed] = SyncPendingChange(
            content: .deletion(of: "tab", schema: 1, modifiedAt: date, modifiedBy: device),
            local: nil,
        )
        state.pending[pinnedHere] = change(tab(.pinned, "here"))
        state.pending[pinned] = change(tab(.pinned, "renamed"))

        state.forgetTodayTabs()

        // Their last accepted content stays, against going back.
        #expect(state.entries[today]?.local == nil && state.entries[today]?.remote == legacy)
        #expect(state.entries[closed]?.local == nil)
        #expect(state.entries[pinned]?.local == tab(.pinned).json)
        #expect(state.pending[today] == nil)
        #expect(state.pending[closed] == nil)
        // Pinned here since: a modification of its record, which leaves.
        #expect(state.pending[pinnedHere] == change(tab(.pinned, "here")))
        #expect(state.pending[pinned] == change(tab(.pinned, "renamed")))
    }
}
