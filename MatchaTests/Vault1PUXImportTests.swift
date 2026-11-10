import Foundation
@testable import Matcha
import Testing

/// Import of a 1Password export (1PUX, `VAULT.md` § 10): a zip archive built here with `ZipWriter`.
struct Vault1PUXImportTests {
    private let exportData = #"""
    { "accounts": [{ "attrs": { "accountName": "Jane" }, "vaults": [{ "attrs": { "name": "Private" }, "items": [
        { "uuid": "a", "favIndex": 1, "createdAt": 1614298956, "categoryUuid": "001", "state": "active",
        "overview": { "title": "GitHub", "url": "https://github.com", "urls": [{ "label": "", "url": "https://github.com/login" }],
            "tags": ["dev"] },
        "details": { "notesPlain": "a note",
            "loginFields": [
            { "value": "jeremy", "id": "", "name": "username", "fieldType": "T", "designation": "username" },
            { "value": "hunter2", "id": "", "name": "password", "fieldType": "P", "designation": "password" },
            { "value": "", "id": "", "name": "remember", "fieldType": "C" } ],
            "sections": [{ "title": "", "fields": [
            { "title": "one-time password", "id": "TOTP_1", "value": { "totp": "otpauth://totp/x?secret=JBSWY3DPEHPK3PXP" } },
            { "title": "recovery", "id": "r", "value": { "concealed": "R-123" } },
            { "title": "linked", "id": "ref", "value": { "reference": "b" } } ] }],
            "passwordHistory": [{ "value": "hunter1", "time": 1600000000 }] } },
        { "uuid": "b", "favIndex": 0, "createdAt": 1614298956, "categoryUuid": "002",
        "overview": { "title": "Visa" },
        "details": { "sections": [{ "title": "", "fields": [
            { "title": "cardholder name", "id": "cardholder", "value": { "string": "Jane Doe" } },
            { "title": "type", "id": "type", "value": { "creditCardType": "visa" } },
            { "title": "number", "id": "ccnum", "value": { "creditCardNumber": "4242424242424242" } },
            { "title": "verification number", "id": "cvv", "value": { "concealed": "123" } },
            { "title": "expiry date", "id": "expiry", "value": { "monthYear": 202708 } },
            { "title": "issuing bank", "id": "bank", "value": { "string": "Big Bank" } } ] }] } },
        { "uuid": "c", "categoryUuid": "004", "overview": { "title": "Me" },
        "details": { "sections": [{ "title": "Identification", "fields": [
            { "title": "first name", "id": "firstname", "value": { "string": "Jane" } },
            { "title": "last name", "id": "lastname", "value": { "string": "Doe" } },
            { "title": "birth date", "id": "birthdate", "value": { "date": -86400 } },
            { "title": "address", "id": "address", "value": { "address": { "street": "1 Main St", "city": "Springfield",
            "country": "us", "zip": "12345", "state": "CA" } } },
            { "title": "email", "id": "email", "value": { "email": { "email_address": "jane@example.com", "provider": null } } } ] }] } },
        { "uuid": "d", "categoryUuid": "006", "overview": { "title": "Scan" },
        "details": { "documentAttributes": { "fileName": "scan.pdf", "documentId": "x", "decryptedSize": 10 } } },
        { "uuid": "e", "categoryUuid": "114", "overview": { "title": "Deploy key" },
        "details": { "sections": [{ "title": "", "fields": [{ "title": "private key", "id": "private_key",
            "value": { "sshKey": { "privateKey": "", "metadata": { "privateKey": "PKCS8_PEM", "publicKey": "", "fingerprint": "",
            "keyType": "ecdsa" } } } }] }] } },
        { "uuid": "f", "categoryUuid": "110", "overview": { "title": "Server" },
        "details": { "sections": [{ "title": "", "fields": [
            { "title": "URL", "id": "url", "value": { "url": "ssh://host.example" } },
            { "title": "admin password", "id": "pw", "value": { "concealed": "root!" } } ] }] } }
    ] }] }] }
    """#

    private func archive(_ json: String) throws -> Data {
        let pem = "-----BEGIN PRIVATE KEY-----\\n\(VaultImportFixtures.p256PKCS8)\\n-----END PRIVATE KEY-----\\n"
        let data = Data(json.replacingOccurrences(of: "PKCS8_PEM", with: pem).utf8)
        return try ZipWriter.archive([("export.attributes", Data(#"{"version":3}"#.utf8)), ("export.data", data)])
    }

    @Test func `a 1PUX archive is recognized and read`() throws {
        let file = try archive(exportData)
        #expect(VaultImporter.format(of: file) == .onePassword)
        let result = try VaultImporter.read(file)
        #expect(result.items.map(\.overview.title) == ["GitHub", "Visa", "Me", "Deploy key", "Server"])
        #expect(result.items.map(\.overview.category) == [.login, .card, .identity, .sshKey, .custom])
        #expect(result.issues == [
            VaultImportIssue(position: 1, title: "GitHub", reason: .unsupportedField("reference"), isItemSkipped: false),
            VaultImportIssue(position: 4, title: "Scan", reason: .attachment, isItemSkipped: true),
        ])
    }

    @Test func `a login keeps its user name, password, code, fields and history`() throws {
        let github = try #require(try Vault1PUXImporter.read(archive(exportData)).items.first)
        #expect(github.overview.favorite)
        #expect(github.overview.tags == ["dev"])
        #expect(github.overview.urls == ["https://github.com/login", "https://github.com"])
        #expect(github.details.createdAt == Date(timeIntervalSince1970: 1_614_298_956))
        let login = try #require(github.details.credential(VaultCredentialType.basicAuth))
        #expect(login.string("username") == "jeremy")
        #expect(login.string("password") == "hunter2")
        #expect(github.details.credential(VaultCredentialType.totp)?.string("secret") == "JBSWY3DPEHPK3PXP")
        #expect(github.details.fields.map { $0.string("label") } == ["recovery"])
        #expect(github.details.history.first?.value == "hunter1")
        #expect(github.details.notes == "a note")
    }

    @Test func `cards, identities, SSH keys and other categories are mapped`() throws {
        let items = try Vault1PUXImporter.read(archive(exportData)).items
        let card = try #require(items[1].details.credential(VaultCredentialType.creditCard))
        #expect(card.string("fullName") == "Jane Doe")
        #expect(card.string("cardType") == "visa")
        #expect(card.string("number") == "4242424242424242")
        #expect(card.string("verificationNumber") == "123")
        #expect(card.string("expiryDate") == "2027-08")
        #expect(items[1].details.fields.map { $0.string("value") } == ["Big Bank"])
        let name = try #require(items[2].details.credential(VaultCredentialType.personName))
        #expect(name.string("given") == "Jane")
        #expect(name.string("surname") == "Doe")
        let address = try #require(items[2].details.credential(VaultCredentialType.address))
        #expect(address.string("country") == "US")
        #expect(address.string("postalCode") == "12345")
        let identityFields = items[2].details.fields.map { [$0.string("type"), $0.string("value")] }
        #expect(identityFields == [["date", "1969-12-31"], ["email", "jane@example.com"]])
        let key = try #require(items[3].details.credential(VaultCredentialType.sshKey))
        #expect(key.string("keyType") == "ecdsa-sha2-nistp256")
        #expect(key.string("privateKey").hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----"))
        #expect(key.string("fingerprint") == VaultImportFixtures.p256Fingerprint)
        let serverFields = items[4].details.fields.map { [$0.string("label"), $0.string("type")] }
        #expect(serverFields == [["URL", "url"], ["admin password", "concealed"]])
    }

    @Test func `an archive without export data, or not an archive, is refused`() throws {
        let other = try ZipWriter.archive([("readme.txt", Data("hello".utf8))])
        #expect(throws: VaultImportError.unknownFormat) { try Vault1PUXImporter.read(other) }
        #expect(throws: VaultImportError.unreadable) { try Vault1PUXImporter.read(Data("PK\u{03}\u{04}garbage".utf8)) }
        #expect(throws: VaultImportError.tooLarge) { try Vault1PUXImporter.read(Data(count: VaultImportLimits.maximumArchiveBytes + 1)) }
    }

    @Test func `export data beyond its ceiling is not unpacked`() throws {
        // 20 MB of spaces compress to a few kilobytes: the announced size is refused before inflating.
        let bomb = try ZipWriter.archive([("export.data", Data(repeating: 0x20, count: VaultImportLimits.maximumTextBytes + 1))])
        #expect(bomb.count < 100_000)
        #expect(throws: VaultImportError.tooLarge) { try Vault1PUXImporter.read(bomb) }
    }
}
