import Foundation
@testable import Matcha
import Testing

/// Two Macs synced through a real sync server (tasks 7.7 to 7.9), run only when one is given, open to registration:
///
///     TEST_RUNNER_MATCHA_SYNC_SERVER=http://127.0.0.1:8181 xcodebuild … test -only-testing:MatchaTests/SyncServerEndToEndTests
///
/// Creates an account, finds the first Mac's data and avatar on the second, follows a change, revokes the second Mac,
/// then deletes the account.
@MainActor
struct SyncServerEndToEndTests {
    private let server = ProcessInfo.processInfo.environment["MATCHA_SYNC_SERVER"]
    private let password = "un mot de passe assez long, 2026"

    /// A simulated Mac: its session, its sync service, its own keychain items.
    private struct Mac {
        let session: BrowserSession
        let sync: SyncService
        let keychain: SyncKeychain
    }

    private func makeMac() throws -> Mac {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = try #require(UserDefaults(suiteName: "SyncServerEndToEndTests-\(UUID().uuidString)"))
        let keychain = SyncKeychain(service: "com.matchabrowser.matcha.sync.tests.\(UUID().uuidString)")
        let sync = SyncService(defaults: defaults, keychain: keychain, extensions: nil, directory: nil)
        sync.start(session: session)
        return Mac(session: session, sync: sync, keychain: keychain)
    }

    /// Waits until `condition` becomes true (20 seconds at most).
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0 ..< 200 {
            if condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    @Test func `two Macs sync through the server`() async throws {
        guard let server else {
            return
        }
        let first = try makeMac()
        let second = try makeMac()
        defer {
            first.keychain.removeDevice()
            second.keychain.removeDevice()
        }
        let home = try #require(first.session.spaces.first)
        first.session.renameSpace(home, to: "Maison")
        let pinned = home.tabManager.newTab(url: URL(string: "https://example.com/epingle"), select: false)
        home.tabManager.setPlace(pinned, to: .pinned)
        home.saveNow()

        // First Mac: account created, kit saved, everything sent, avatar set.
        let endpoint = try await first.sync.checkServer(server)
        let email = "e2e-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let kit = try await first.sync.createAccount(on: endpoint, email: email, password: password, invitation: nil)
        #expect(SyncRecoveryKey(text: kit.recoveryKey) != nil)
        first.sync.recoveryKitSaved()
        #expect(try await eventually { first.sync.coordinator?.lastSyncDate != nil })
        let picture = try #require(AvatarImage.initials("JM", color: "#34C759"))
        try await first.sync.setAvatar(picture)

        // Second Mac, with only its first-launch data: it takes the synced data.
        try await second.sync.signIn(on: endpoint, email: email, password: password)
        #expect(try await eventually { second.session.spaces.first?.record.name == "Maison" })
        let mirror = try #require(second.session.spaces.first)
        #expect(try await eventually { mirror.tabManager.tab(withID: pinned.id) != nil })
        #expect(try await eventually { second.sync.avatar == picture })

        // A change on the first Mac reaches the second (event stream).
        first.session.renameSpace(home, to: "Chez moi")
        #expect(try await eventually { second.session.spaces.first?.record.name == "Chez moi" })

        // The first Mac disconnects the second: its next request ends its session, it keeps its data.
        let devices = try await first.sync.devices()
        #expect(devices.count == 2)
        let other = try #require(devices.first { $0.current != true })
        try await first.sync.revokeDevice(other.id)
        await second.sync.coordinator?.syncNow()
        #expect(try await eventually { second.sync.configuration.signedOutReason == .deviceRevoked })
        #expect(second.session.spaces.first?.record.name == "Chez moi")

        try await first.sync.deleteAccount(password: password)
        #expect(first.sync.configuration == SyncConfiguration())
    }
}
