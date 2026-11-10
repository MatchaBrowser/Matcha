import Foundation
@testable import Matcha
import Testing

/// Import of an unencrypted Bitwarden JSON export (`VAULT.md` § 10).
struct VaultBitwardenImportTests {
    private let export = #"""
    {
        "encrypted": false,
        "folders": [{ "id": "f1", "name": "Work" }],
        "items": [
        { "id": "1", "type": 1, "name": "GitHub", "folderId": "f1", "favorite": true, "notes": "recovery codes in the safe",
            "creationDate": "2024-03-01T10:00:00.000Z", "revisionDate": "2024-04-01T10:00:00.000Z",
            "login": { "username": "jeremy", "password": "new", "totp": "otpauth://totp/GitHub:jeremy?secret=JBSWY3DPEHPK3PXP",
                "uris": [{ "match": 1, "uri": "https://github.com/login" }, { "match": null, "uri": "https://gist.github.com" }],
                "fido2Credentials": [{ "credentialId": "x" }] },
            "passwordHistory": [{ "lastUsedDate": "2024-03-15T10:00:00.000Z", "password": "old" }],
            "fields": [
            { "name": "PIN", "value": "1234", "type": 1 }, { "name": "Region", "value": "eu", "type": 0 },
            { "name": "Admin", "value": "TRUE", "type": 2 }, { "name": "Linked", "value": null, "type": 3, "linkedId": 100 }
            ] },
        { "id": "2", "type": 2, "name": "Alarm", "notes": "code 4321", "secureNote": { "type": 0 } },
        { "id": "3", "type": 3, "name": "Visa", "card": { "cardholderName": "Jane Doe", "brand": "Visa",
            "number": "4111 1111 1111 1111", "expMonth": "4", "expYear": "27", "code": "123" } },
        { "id": "4", "type": 4, "name": "Me", "identity": { "title": "Dr", "firstName": "Jane", "middleName": "Q", "lastName": "Doe",
            "address1": "1 Main St", "address2": "Apt 2", "city": "Springfield", "state": "CA", "postalCode": "12345", "country": "US",
            "email": "jane@example.com", "phone": "+1 555", "ssn": "123-45-6789", "company": null } },
        { "id": "5", "type": 5, "name": "Laptop key", "sshKey": { "privateKey": "SSH_KEY",
            "publicKey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJcpkKjnk96NJj8WfMLUHcdg37lm0KLP0zGA12PxGgCw",
            "keyFingerprint": "SHA256:sfzLWxVtWOo88cP8tGyLGygC+BvS55tO0v6D/gVZ1lo" } },
        { "id": "6", "type": 6, "name": "Bank", "bankAccount": { "iban": "FR76" } },
        "not an item"
        ]
    }
    """#

    private func read() throws -> VaultImportResult {
        let key = VaultImportFixtures.ed25519OpenSSH.replacingOccurrences(of: "\n", with: "\\n")
        let json = export.replacingOccurrences(of: "SSH_KEY", with: key)
        return try VaultBitwardenImporter.read(Data(json.utf8))
    }

    @Test func `a login keeps its addresses, code, fields, history and folder`() throws {
        let github = try #require(try read().items.first)
        #expect(github.overview.category == .login)
        #expect(github.overview.title == "GitHub")
        #expect(github.overview.favorite)
        #expect(github.overview.tags == ["Work"])
        #expect(github.overview.urls == ["https://github.com/login", "https://gist.github.com"])
        #expect(github.overview.match == .host)
        #expect(github.details.createdAt == SyncCoding.date(from: "2024-03-01T10:00:00.000Z"))
        let login = try #require(github.details.credential(VaultCredentialType.basicAuth))
        #expect(login.string("username") == "jeremy")
        #expect(login.string("password") == "new")
        #expect(github.details.credential(VaultCredentialType.totp)?.string("secret") == "JBSWY3DPEHPK3PXP")
        #expect(github.details.history.map(\.field) == ["\(login.id).password"])
        #expect(github.details.history.map(\.value) == ["old"])
        let fields = github.details.fields.map { [$0.string("label"), $0.string("type"), $0.string("value")] }
        #expect(fields == [["PIN", "concealed", "1234"], ["Region", "text", "eu"], ["Admin", "text", "true"]])
        #expect(Set(github.details.fields.map(\.id)).count == 3)
        #expect(github.details.notes == "recovery codes in the safe")
    }

    @Test func `notes, cards, identities and SSH keys take their categories`() throws {
        let items = try read().items
        #expect(items.map(\.overview.category) == [.login, .note, .card, .identity, .sshKey])
        #expect(items[1].details.notes == "code 4321")
        let card = try #require(items[2].details.credential(VaultCredentialType.creditCard))
        #expect(card.string("fullName") == "Jane Doe")
        #expect(card.string("cardType") == "Visa")
        #expect(card.string("number") == "4111 1111 1111 1111")
        #expect(card.string("expiryDate") == "2027-04")
        #expect(card.string("verificationNumber") == "123")
        #expect(items[2].overview.subtitle == "•••• 1111")
        let name = try #require(items[3].details.credential(VaultCredentialType.personName))
        #expect([name.string("title"), name.string("given"), name.string("given2"), name.string("surname")] == ["Dr", "Jane", "Q", "Doe"])
        let address = try #require(items[3].details.credential(VaultCredentialType.address))
        #expect(address.string("streetAddress") == "1 Main St\nApt 2")
        #expect(address.string("territory") == "CA")
        #expect(items[3].details.fields.map { $0.string("type") } == ["email", "phone", "concealed"])
        let key = try #require(items[4].details.credential(VaultCredentialType.sshKey))
        #expect(key.string("privateKey") == VaultImportFixtures.ed25519OpenSSH)
        #expect(key.string("keyType") == "ssh-ed25519")
        #expect(key.string("fingerprint") == VaultImportFixtures.ed25519Fingerprint)
        #expect(items[4].overview.subtitle == VaultImportFixtures.ed25519Fingerprint)
    }

    @Test func `passkeys, linked fields, unknown types and malformed items are reported`() throws {
        let issues = try read().issues
        #expect(issues == [
            VaultImportIssue(position: 1, title: "GitHub", reason: .passkey, isItemSkipped: false),
            VaultImportIssue(position: 1, title: "GitHub", reason: .linkedField, isItemSkipped: false),
            VaultImportIssue(position: 6, title: "Bank", reason: .unsupportedType("6"), isItemSkipped: true),
            VaultImportIssue(position: 7, title: "", reason: .unreadable, isItemSkipped: true),
        ])
    }

    @Test func `an encrypted export is refused`() {
        let passwordProtected = #"{"encrypted": true, "passwordProtected": true, "salt": "c2FsdA==", "kdfType": 0, "data": "2.x"}"#
        let accountKey = #"{"encrypted": true, "encKeyValidation_DO_NOT_EDIT": "2.x", "folders": [], "items": [{"name": "2.y"}]}"#
        #expect(throws: VaultImportError.encryptedExport) { try VaultBitwardenImporter.read(Data(passwordProtected.utf8)) }
        #expect(throws: VaultImportError.encryptedExport) { try VaultBitwardenImporter.read(Data(accountKey.utf8)) }
        #expect(VaultImporter.format(of: Data(passwordProtected.utf8)) == .bitwarden)
    }

    @Test func `other JSON is not a Bitwarden export`() {
        #expect(throws: VaultImportError.unknownFormat) { try VaultBitwardenImporter.read(Data(#"{"items": 3}"#.utf8)) }
        #expect(throws: VaultImportError.unreadable) { try VaultBitwardenImporter.read(Data("{".utf8)) }
        #expect(throws: VaultImportError.unreadable) { try VaultBitwardenImporter.read(Data(#"{"encrypted": false}"#.utf8)) }
    }

    @Test func `card expiry dates are written as year and month`() {
        #expect(VaultBitwardenImporter.expiryDate(month: "04", year: "2027") == "2027-04")
        #expect(VaultBitwardenImporter.expiryDate(month: "12", year: "9") == "2009-12")
        #expect(VaultBitwardenImporter.expiryDate(month: "13", year: "2027").isEmpty)
        #expect(VaultBitwardenImporter.expiryDate(month: "", year: "2027").isEmpty)
    }
}
