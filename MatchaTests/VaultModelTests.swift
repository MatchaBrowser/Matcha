import Foundation
@testable import Matcha
import Testing

/// The rules of the items of the vault (`VAULT.md` § 5.4, § 9): merges without loss, history, the form and its round
/// trip, and the strict reading of the answer to an atomic push.
struct VaultModelTests {
    private func login(password: String, username: String = "jeremy", at date: Date, by device: UUID = UUID()) -> VaultItemContent {
        var content = VaultItemContent()
        content.overview.category = .login
        content.overview.title = "Example"
        content.overview.modifiedAt = date
        content.overview.modifiedBy = device
        content.details.credentials = [VaultEntry([
            "id": .string("C1"), "type": .string(VaultCredentialType.basicAuth),
            "username": .string(username), "password": .string(password),
        ])]
        return content
    }

    private func password(_ content: VaultItemContent) -> String {
        content.details.credential(VaultCredentialType.basicAuth)?.string("password") ?? ""
    }

    @Test func `a password changed on both sides keeps the loser in the history`() {
        let base = login(password: "base", at: Date(timeIntervalSince1970: 100))
        let local = login(password: "local", at: Date(timeIntervalSince1970: 200))
        let remote = login(password: "remote", at: Date(timeIntervalSince1970: 300))
        let merged = VaultMerge.merged(local: local, remote: remote, base: base)
        #expect(password(merged) == "remote")
        #expect(merged.details.history.map(\.value).contains("local"))
    }

    @Test func `fields changed on one side each are both kept`() {
        let base = login(password: "base", at: Date(timeIntervalSince1970: 100))
        var local = login(password: "new", at: Date(timeIntervalSince1970: 200))
        local.overview.title = "Example"
        var remote = login(password: "base", username: "jeremy.mouton", at: Date(timeIntervalSince1970: 300))
        remote.overview.title = "Renamed"
        let merged = VaultMerge.merged(local: local, remote: remote, base: base)
        #expect(password(merged) == "new")
        #expect(merged.details.credential(VaultCredentialType.basicAuth)?.string("username") == "jeremy.mouton")
        #expect(merged.overview.title == "Renamed")
    }

    @Test func `an entry added on one side and one removed on the other`() {
        let base = login(password: "base", at: Date(timeIntervalSince1970: 100))
        var local = base
        local.details.fields = [VaultEntry([
            "id": .string("F1"),
            "label": .string("PIN"),
            "type": .string("concealed"),
            "value": .string("1234"),
        ])]
        var remote = base
        remote.details.credentials = []
        remote.overview.modifiedAt = Date(timeIntervalSince1970: 300)
        let merged = VaultMerge.merged(local: local, remote: remote, base: base)
        #expect(merged.details.fields.count == 1)
        #expect(merged.details.credentials.isEmpty)
    }

    @Test func `a reconciliation keeps the newer version and the other's secrets`() {
        let older = login(password: "older", at: Date(timeIntervalSince1970: 100))
        let newer = login(password: "newer", at: Date(timeIntervalSince1970: 200))
        let reconciled = VaultMerge.reconciled(older, newer)
        #expect(password(reconciled) == "newer")
        #expect(reconciled.details.history.map(\.value) == ["older"])
        #expect(VaultMerge.reconciled(newer, older) == reconciled)
    }

    @Test func `the history is bounded per secret and in all`() {
        var content = login(password: "now", at: .now)
        for index in 0 ..< 30 {
            content.addHistory(VaultHistoryEntry(
                field: "C1.password",
                value: "v\(index)",
                date: Date(timeIntervalSince1970: Double(index)),
            ))
        }
        #expect(content.details.history.count == VaultItemContent.historyPerSecret)
        #expect(content.details.history.first?.value == "v29")
        content.addHistory(VaultHistoryEntry(field: "C1.password", value: "v29", date: .now))
        #expect(content.details.history.count == VaultItemContent.historyPerSecret)
    }

    @Test func `the form writes back onto the content and keeps what it doesn't show`() throws {
        var content = login(password: "secret", at: .now)
        content.overview.extra["future"] = .string("kept")
        content.details.credentials.append(VaultEntry(["id": .string("X"), "type": .string("passkey"), "rpId": .string("example.com")]))
        var draft = VaultItemDraft(id: UUID(), content: content)
        #expect(draft.value(VaultFieldSpec.login[1]) == "secret")
        draft.values[VaultFieldSpec.login[1].id] = "changed"
        draft.values[VaultFieldSpec.login[2].id] = "JBSWY3DPEHPK3PXP"
        let written = try draft.content()
        #expect(password(written) == "changed")
        #expect(written.overview.extra["future"] == .string("kept"))
        #expect(written.details.credential("passkey") != nil)
        #expect(written.details.credential(VaultCredentialType.totp)?.string("secret") == "JBSWY3DPEHPK3PXP")
        #expect(written.overview.subtitle == "jeremy")
        #expect(!written.isEditable)
    }

    @Test func `a one-time code is read from a secret or an otpauth address`() throws {
        #expect(try VaultItemDraft.oneTimeCode(from: "JBSW Y3DP EHPK 3PXP").digits == 6)
        let uri = "otpauth://totp/Example:jeremy?secret=JBSWY3DPEHPK3PXP&issuer=Example&digits=8&period=60"
        let code = try VaultItemDraft.oneTimeCode(from: uri)
        #expect(code.digits == 8 && code.period == 60 && code.issuer == "Example")
        #expect(throws: (any Error).self) { try VaultItemDraft.oneTimeCode(from: "not base 32!") }
    }

    @Test func `an atomic answer is all applied or not applied at all`() throws {
        let ids = [UUID(), UUID()]
        let changes = ids.map { SyncServerChange(id: $0, baseVersion: nil, deleted: false, keyVersion: 1, payload: "") }
        let batch = VaultBatch(kind: .atomic, key: UUID(), changes: changes)
        let applied = ids.map { SyncServerPushResult(id: $0, status: "applied", version: 7, current: nil, code: nil) }
        #expect(try VaultPusher.outcome(of: applied, for: batch) == .applied([ids[0]: 7, ids[1]: 7]))
        let conflict = [
            SyncServerPushResult(id: ids[0], status: "aborted", version: nil, current: nil, code: nil),
            SyncServerPushResult(id: ids[1], status: "conflict", version: nil, current: nil, code: nil),
        ]
        #expect(try VaultPusher.outcome(of: conflict, for: batch) == .conflict(applied: [:]))
        let mixed = [applied[0], conflict[1]]
        #expect(throws: SyncClientError.unreadableAnswer) { try VaultPusher.outcome(of: mixed, for: batch) }
        #expect(throws: SyncClientError.unreadableAnswer) { try VaultPusher.outcome(of: [applied[0]], for: batch) }
        let repair = VaultBatch(kind: .repair, key: UUID(), changes: changes)
        #expect(throws: SyncClientError.unreadableAnswer) { try VaultPusher.outcome(of: conflict, for: repair) }
    }
}
