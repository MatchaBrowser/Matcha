import Foundation
@testable import Matcha
import Testing

/// The entry point of the import (format, bounded reading), the one-time codes and the duplicates (`VAULT.md` § 10).
struct VaultImporterTests {
    private func login(_ url: String, _ username: String, _ password: String, trashed: Bool = false) -> VaultItemContent {
        var draft = VaultImportDraft(position: 1, title: "", category: .login)
        draft.addURL(url)
        draft.addCredential(VaultCredentialType.basicAuth, ["username": username, "password": password])
        var item = draft.finished().content
        item.overview.trashedAt = trashed ? .now : nil
        return item
    }

    @Test func `the format is recognized by the content`() {
        #expect(VaultImporter.format(of: Data("name,url,username,password,note\n".utf8)) == .csv)
        #expect(VaultImporter.format(of: Data("\u{FEFF}\"Title\",\"URL\",\"Username\",\"Password\"\r\n".utf8)) == .csv)
        #expect(VaultImporter.format(of: Data(#" {"encrypted": false, "folders": [], "items": []}"#.utf8)) == .bitwarden)
        #expect(VaultImporter.format(of: Data(#"{"version": {"major": 1}, "accounts": []}"#.utf8)) == .cxf)
        #expect(VaultImporter.format(of: Data(#"{"something": "else"}"#.utf8)) == nil)
        #expect(VaultImporter.format(of: Data("hello, world\n".utf8)) == nil)
        #expect(VaultImporter.format(of: Data()) == nil)
        #expect(throws: VaultImportError.unknownFormat) { try VaultImporter.read(Data("hello".utf8)) }
    }

    @Test func `a file is read within its ceiling`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("export.csv")
        try Data("url,username,password\n".utf8).write(to: url)
        #expect(try VaultImporter.contents(of: url) == Data("url,username,password\n".utf8))
        #expect(throws: VaultImportError.tooLarge) { try VaultImporter.contents(of: url, limit: 10) }
        #expect(throws: VaultImportError.unreadable) { try VaultImporter.contents(of: directory.appendingPathComponent("missing")) }
    }

    @Test func `one-time code setups are read within what Matcha computes`() {
        let uri = "otpauth://totp/ACME Co:john@example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=&period=15"
        let totp = VaultOTPAuth.credential(from: uri)
        #expect(totp?.string("secret") == "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ")
        #expect(totp?.string("issuer") == "ACME Co")
        #expect(totp?.integer("period") == 15)
        #expect(totp?.string("algorithm") == "sha1")
        #expect(VaultOTPAuth.credential(from: "jbsw y3dp ehpk 3pxp")?.string("secret") == "JBSWY3DPEHPK3PXP")
        #expect(VaultOTPAuth.credential(from: "otpauth://totp/x?secret=JBSWY3DP&digits=10") == nil)
        #expect(VaultOTPAuth.credential(from: "otpauth://totp/x?secret=JBSWY3DP&period=5") == nil)
        #expect(VaultOTPAuth.credential(from: "otpauth://totp/x?secret=JBSWY3DP&algorithm=MD5") == nil)
        #expect(VaultOTPAuth.credential(from: "otpauth://totp/x?issuer=nosecret") == nil)
        #expect(VaultOTPAuth.credential(from: "steam://ABCDEF") == nil)
        #expect(VaultOTPAuth.credential(from: "JBSWY3DP1") == nil)
    }

    @Test func `duplicates share the site, the user name and the password`() {
        let existing = [
            login("https://www.github.com/login", "jeremy", "pw"),
            login("https://example.com", "bob", "pw", trashed: true),
        ]
        let drafts = [
            login("https://github.com/settings", "jeremy", "pw"),
            login("github.com", "jeremy", "other"),
            login("https://gist.github.com", "jeremy", "pw"),
            login("https://example.com", "bob", "pw"),
            login("https://example.com/again", "bob", "pw"),
            VaultItemContent(),
        ]
        #expect(VaultImportDuplicates.duplicates(in: drafts, existing: existing) == IndexSet([0, 4]))
        #expect(VaultImportDraft.host(of: "HTTPS://WWW.Example.COM:8443/path") == "example.com")
        #expect(VaultImportDraft.host(of: "example.org/login").isEmpty == false)
    }

    @Test func `a draft that keeps nothing is skipped with the reason of what was dropped`() {
        var dropped = VaultImportDraft(position: 3, title: "Passkey only")
        dropped.issues.append(.passkey)
        var result = VaultImportResult()
        result.add(dropped)
        var titleOnly = VaultImportDraft(position: 4, title: "Empty note", category: .note)
        titleOnly.addNotes("  ")
        result.add(titleOnly)
        #expect(result.items.map(\.overview.title) == ["Empty note"])
        #expect(result.issues == [VaultImportIssue(position: 3, title: "Passkey only", reason: .passkey, isItemSkipped: true)])
    }
}
