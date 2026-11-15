import Foundation
@testable import Matcha
import Testing

/// Import of the CSV of Chrome, Safari and Firefox (`VAULT.md` § 10): RFC 4180, columns found by their names.
struct VaultCSVImportTests {
    private func read(_ text: String) throws -> VaultImportResult {
        try VaultCSVImporter.read(Data(text.utf8))
    }

    private func login(_ item: VaultItemContent) -> VaultEntry? {
        item.details.credential(VaultCredentialType.basicAuth)
    }

    // MARK: Parser

    @Test func `quoted fields keep their commas, doubled quotes and line breaks`() throws {
        let text = "a,\"b, c\",\"say \"\"hi\"\"\"\r\n\"multi\nline\",,\"\"\nlast,é,\"\"\"\""
        let records = try VaultCSVParser.records(of: Data(text.utf8))
        #expect(records == [["a", "b, c", "say \"hi\""], ["multi\nline", "", ""], ["last", "é", "\""]])
    }

    @Test func `a byte order mark, CR alone and blank lines are handled`() throws {
        let records = try VaultCSVParser.records(of: Data([0xEF, 0xBB, 0xBF]) + Data("x,y\r\rz\n\n".utf8))
        #expect(records == [["x", "y"], ["z"]])
    }

    @Test func `an unclosed quote or text that isn't UTF-8 is unreadable`() {
        #expect(throws: VaultImportError.unreadable) { try VaultCSVParser.records(of: Data("a,\"never closed\nb".utf8)) }
        #expect(throws: VaultImportError.unreadable) { try VaultCSVParser.records(of: Data([0x61, 0x2C, 0xFF, 0xFE])) }
    }

    @Test func `too many fields or records are refused`() {
        let wide = String(repeating: ",", count: VaultImportLimits.maximumFieldsPerRecord)
        #expect(throws: VaultImportError.unreadable) { try VaultCSVParser.records(of: Data(wide.utf8)) }
        let tall = String(repeating: "a\n", count: VaultImportLimits.maximumRecords + 1)
        #expect(throws: VaultImportError.tooLarge) { try VaultCSVParser.records(of: Data(tall.utf8)) }
    }

    // MARK: Browsers

    @Test func `a Chrome export becomes logins`() throws {
        let csv = "\u{FEFF}name,url,username,password,note\r\n"
            + "github.com,https://github.com/login,jeremy,\"p,a\"\"ss\",\"line 1\nline 2\"\r\n"
            + ",https://www.example.com/,bob,secret,\r\n"
        let result = try read(csv)
        #expect(result.items.count == 2)
        #expect(result.issues.isEmpty)
        let github = result.items[0]
        #expect(github.overview.category == .login)
        #expect(github.overview.title == "github.com")
        #expect(github.overview.subtitle == "jeremy")
        #expect(github.overview.urls == ["https://github.com/login"])
        #expect(login(github)?.string("username") == "jeremy")
        #expect(login(github)?.string("password") == "p,a\"ss")
        #expect(login(github)?.id.isEmpty == false)
        #expect(github.details.notes == "line 1\nline 2")
        #expect(github.overview.modifiedAt == nil)
        // Without a name, the title is the host.
        #expect(result.items[1].overview.title == "example.com")
    }

    @Test func `a Safari export brings its one-time codes`() throws {
        let csv = """
        Title,URL,Username,Password,Notes,OTPAuth
        GitHub (jeremy),https://github.com,jeremy,pw1,,otpauth://totp/GitHub:j?secret=jbsw%20y3dp&digits=8&period=60&algorithm=SHA256
        Broken,https://example.com,bob,pw2,a note,otpauth://hotp/x?secret=JBSWY3DP
        """
        let result = try read(csv)
        #expect(result.items.count == 2)
        let totp = try #require(result.items[0].details.credential(VaultCredentialType.totp))
        #expect(totp.string("secret") == "JBSWY3DP")
        #expect(totp.string("algorithm") == "sha256")
        #expect(totp.integer("digits") == 8)
        #expect(totp.integer("period") == 60)
        #expect(totp.string("issuer") == "GitHub")
        #expect(result.items[0].overview.title == "GitHub (jeremy)")
        // An HOTP setup: the login is imported, the code reported.
        #expect(result.items[1].details.credential(VaultCredentialType.totp) == nil)
        #expect(result.issues == [VaultImportIssue(position: 2, title: "Broken", reason: .invalidOneTimeCode, isItemSkipped: false)])
    }

    @Test func `a Firefox export dates its logins`() throws {
        let csv = """
        "url","username","password","httpRealm","formActionOrigin","guid","timeCreated","timeLastUsed","timePasswordChanged"
        "https://accounts.example.org","alice","pw","","https://accounts.example.org","{1}","1700000000123","1700000000123","1700000000123"
        """
        let item = try #require(try read(csv).items.first)
        #expect(item.overview.title == "accounts.example.org")
        #expect(item.details.createdAt == Date(timeIntervalSince1970: 1_700_000_000.123))
        #expect(login(item)?.string("username") == "alice")
    }

    @Test func `columns are found by name, in any case and order, and may be missing`() throws {
        let csv = "PASSWORD, Username ,Url\nsecret,carol\n,,https://empty.example\n"
        let result = try read(csv)
        // The first record lacks its URL; the second has nothing to import.
        #expect(result.items.count == 1)
        #expect(login(result.items[0])?.string("password") == "secret")
        #expect(result.items[0].overview.urls.isEmpty)
        #expect(result.issues == [VaultImportIssue(position: 2, title: "", reason: .empty, isItemSkipped: true)])
        #expect(result.skippedCount == 1)
    }

    @Test func `an unknown header or a file too large is refused`() {
        #expect(throws: VaultImportError.unknownFormat) { try read("title,login,secret\na,b,c\n") }
        #expect(throws: VaultImportError.unknownFormat) { try read("") }
        let large = Data(count: VaultImportLimits.maximumTextBytes + 1)
        #expect(throws: VaultImportError.tooLarge) { try VaultCSVImporter.read(large) }
    }

    @Test func `notes beyond the limit of an item skip it`() throws {
        let notes = String(repeating: "n", count: VaultDetails.maximumNotesBytes + 1)
        let result = try read("url,username,password,note\nhttps://a.example,u,p,\(notes)\n")
        #expect(result.items.isEmpty)
        #expect(result.issues.map(\.reason) == [.tooLarge])
    }
}
