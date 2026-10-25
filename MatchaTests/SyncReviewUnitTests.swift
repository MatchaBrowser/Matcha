import Foundation
@testable import Matcha
import Testing

/// Pure parts of the sync fixes of the review (section SY).
struct SyncReviewUnitTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Review SY8: a replaced version dated in 2030 dates this modification only, never the next ones.
    @Test func `a replaced date far in the future doesn't move the clock`() {
        var clock = SyncClock()
        let future = now.addingTimeInterval(4 * 365 * 24 * 60 * 60)
        let replacing = clock.next(now: now, after: future)
        #expect(replacing > future)
        let next = clock.next(now: now.addingTimeInterval(1))
        #expect(next.timeIntervalSince(now) < 2)
        // Within the lead allowed, the clock follows the replaced version as before.
        let soon = now.addingTimeInterval(60 * 60)
        #expect(clock.next(now: now, after: soon) > soon)
        #expect(clock.next(now: now) > soon)
    }

    /// Review SY14: old deletions and orphans are forgotten, never a pending change.
    @Test func `old deletions and orphans are purged`() {
        var state = SyncState()
        let old = now.addingTimeInterval(-200 * 24 * 60 * 60)
        func content(_ date: Date, deleted: Bool) -> SyncContent {
            SyncContent(type: "profile", schema: 1, modifiedAt: date, modifiedBy: UUID(), deleted: deleted, fields: .emptyObject)
        }
        let deletion = UUID(), recent = UUID(), orphan = UUID(), live = UUID(), pending = UUID()
        state.entries[deletion] = SyncEntry(type: "profile", version: 1, remote: content(old, deleted: true))
        state.entries[recent] = SyncEntry(type: "profile", version: 2, remote: content(now, deleted: true))
        var waiting = SyncEntry(type: "profile", version: 3, remote: content(old, deleted: false))
        waiting.isWaiting = true
        state.entries[orphan] = waiting
        state.entries[live] = SyncEntry(type: "profile", version: 4, remote: content(old, deleted: false), local: .emptyObject)
        state.entries[pending] = SyncEntry(type: "profile", version: 5, remote: content(old, deleted: true))
        state.pending[pending] = SyncPendingChange(content: content(now, deleted: false), local: .emptyObject)
        state.purgeOldEntries(now: now)
        #expect(Set(state.entries.keys) == [recent, live, pending])
    }

    /// Review SY25: nested folders received together are written parents first.
    @Test func `nested folders received together are written parents first`() {
        let space = UUID(), top = UUID(), middle = UUID(), bottom = UUID()
        func folder(_ parent: UUID?) -> SyncFields {
            .folder(SyncFolderFields(name: "F", order: 0, isCollapsed: false, spaceId: space, parentId: parent))
        }
        let changes: [SyncLocalChange] = [.upsert(bottom, folder(middle)), .upsert(middle, folder(top)), .upsert(top, folder(nil))]
        #expect(SyncLocalChange.ordered(changes).map(\.id) == [top, middle, bottom])
    }

    /// Review SY27: the warning about a Mac ahead goes away after a week.
    @Test func `the future date warning expires`() {
        var state = SyncState()
        #expect(!state.showsFutureDateWarning(now: now))
        state.futureDateSeenAt = now
        #expect(state.showsFutureDateWarning(now: now.addingTimeInterval(60)))
        #expect(!state.showsFutureDateWarning(now: now.addingTimeInterval(8 * 24 * 60 * 60)))
    }

    /// Review SY16: a package too large isn't tried again for its version; a refused one waits longer each time.
    @Test func `a package that can't be sent waits`() {
        let tooLarge = SyncedPackageFailure(version: "1", isTooLarge: true, attempts: 1, failedAt: now)
        #expect(!tooLarge.allowsAttempt(at: now.addingTimeInterval(24 * 60 * 60)))
        let refused = SyncedPackageFailure(version: "1", isTooLarge: false, attempts: 3, failedAt: now)
        #expect(!refused.allowsAttempt(at: now.addingTimeInterval(3 * 60)))
        #expect(refused.allowsAttempt(at: now.addingTimeInterval(4 * 60)))
        let many = SyncedPackageFailure(version: "1", isTooLarge: false, attempts: 30, failedAt: now)
        #expect(many.allowsAttempt(at: now.addingTimeInterval(6 * 60 * 60)))
    }

    /// Review SY16: the archive stops as soon as it passes its limit.
    @Test func `the archive stops at its limit`() throws {
        let entries = (0 ..< 10).map { index in (
            path: "file-\(index)",
            contents: Data((0 ..< 4096).map { _ in UInt8.random(in: 0 ... 255) }),
        ) }
        #expect(throws: ZipWriter.Failure.tooLarge) { try ZipWriter.archive(entries, limit: 8192) }
        #expect(try ZipWriter.archive(entries, limit: 1_000_000).count > 40000)
    }

    /// Review SY4: renewed tokens the keychain refuses are used from memory and written again later.
    @Test func `renewed tokens survive a failed keychain write`() async throws {
        let writes = Writes()
        let tokens = SyncTokenStore(accessToken: "old", refreshToken: "refresh-1") { renewed in
            try writes.write(renewed.refreshToken)
        }
        writes.fails = true
        let access = try await tokens.renewed(after: "old") { _ in SyncRefreshResponse(accessToken: "new", refreshToken: "refresh-2") }
        #expect(access == "new")
        #expect(await tokens.isUnsaved)
        writes.fails = false
        await tokens.saveIfNeeded()
        #expect(await !tokens.isUnsaved)
        #expect(writes.saved == ["refresh-2"])
    }

    /// Keychain writes, failing on demand.
    private final class Writes: @unchecked Sendable {
        private let lock = NSLock()
        private var failing = false
        private var written: [String] = []

        var fails: Bool {
            get { lock.withLock { failing } }
            set { lock.withLock { failing = newValue } }
        }

        var saved: [String] {
            lock.withLock { written }
        }

        func write(_ token: String) throws {
            try lock.withLock {
                if failing {
                    throw SyncClientError.keychain(-25308)
                }
                written.append(token)
            }
        }
    }
}
