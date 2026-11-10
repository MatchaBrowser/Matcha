import Foundation
@testable import Matcha
import Testing

/// Import of a CXF document: the example of the specification (CXF 1.0, Appendix A, as corrected by the errata of
/// 2026-03-09), its values shortened to one line per credential.
struct VaultCXFReaderTests {
    private static func field(_ type: String, _ value: String) -> String {
        #"{ "fieldType": "\#(type)", "value": "\#(value)", "label": "L" }"#
    }

    private let example = #"""
    { "version": { "major": 1, "minor": 0 }, "exporterRpId": "exporter.example.com", "exporterDisplayName": "Exporter app",
        "timestamp": 1705228800,
        "accounts": [{ "id": "DZSXp7iBQY-Fg-OofakQtQ", "username": "jane_smith", "email": "jane.smith@example.com",
        "collections": [{ "id": "0dimBl7dRRyPLGKGxEEm5Q", "title": "Work Accounts", "items": [
            { "item": "TMrjj3uIRtitVmIpiwXmyg" }, { "item": "Z4cFmc21Q5-vCVwd1wJx1g" }, { "item": "9OF-QjVDQo2Wp2xWPw6ZhA" }] }],
        "items": [
            { "id": "9OF-QjVDQo2Wp2xWPw6ZhA", "creationAt": 1705142400, "modifiedAt": 1705228800, "title": "GitHub Login",
            "subtitle": "Work GitHub account", "scope": { "urls": ["https://github.com"], "androidApps": [] },
            "tags": ["development", "git"],
            "credentials": [
                { "type": "basic-auth", "username": { "fieldType": "string", "value": "johndoe" },
                "password": { "fieldType": "concealed-string", "value": "securepassword123" } },
                { "type": "totp", "secret": "JBSWY3DPEHPK3PXP", "period": 30, "digits": 6, "issuer": "GitHub", "algorithm": "sha256",
                "username": "jane.smith@example.com" }] },
            { "id": "akKA3Y0jQRuK7sKplB0Y9w", "title": "WebAuthn.io", "credentials": [{ "type": "passkey", "credentialId": "Y3Jl",
            "rpId": "webauthn.io", "username": "johndoe", "userDisplayName": "John Doe", "userHandle": "cnEz", "key": "MIGH" }] },
            { "id": "iz0Q6JWoQ_CbDRboCPJ1Tg", "title": "Visa Credit Card", "tags": ["finance"], "credentials": [{ "type": "credit-card",
            "number": CONCEALED(4111111111111111), "fullName": STRING(John Doe), "cardType": STRING(Visa),
            "verificationNumber": CONCEALED(123), "pin": CONCEALED(0000), "expiryDate": MONTH(2027-08), "validFrom": MONTH(2024-02) }] },
            { "id": "2cGy6PNOSQ2cW43NVxjGSg", "title": "Wifi", "credentials": [{ "type": "wifi", "ssid": STRING(Home_Network),
            "networkSecurityType": { "fieldType": "wifi-network-security-type", "value": "wpa2-personal", "label": "Security Type" },
            "passphrase": CONCEALED(mypassword123), "hidden": { "fieldType": "boolean", "value": "false" } }] },
            { "id": "s4TK1UNTRhG4j1DQawUz8g", "title": "Home alarm", "credentials": [{ "type": "note",
            "content": STRING(some instructionts to enable/disable the alarm) }] },
            { "id": "BQzS9Ws3RnOabLzFuyOu7Q", "title": "Driver License", "credentials": [{ "type": "drivers-license",
            "fullName": STRING(John Doe), "birthDate": DATE(1990-05-15), "expiryDate": DATE(2030-06-01),
            "territory": { "fieldType": "subdivision-code", "value": "US-CA" }, "country": { "fieldType": "country-code", "value": "US" },
            "licenseNumber": STRING(D12345678), "licenseClass": STRING(C) }] },
            { "id": "HHl63ybfQG6GBRHlyrvKfg", "title": "House Address", "credentials": [{ "type": "address",
            "streetAddress": STRING(123 Main Street), "postalCode": STRING(12345), "city": STRING(Springfield),
            "territory": { "fieldType": "subdivision-code", "value": "US-CA" }, "tel": STRING(+1-555-123-4567) }] },
            { "id": "Z4cFmc21Q5-vCVwd1wJx1g", "title": "SSH Key", "credentials": [{ "type": "ssh-key", "keyType": "ssh-rsa",
            "privateKey": "RSA_KEY", "keyComment": "Work SSH Key", "creationDate": DATE(2023-01-01) }] },
            { "id": "EWM-4m3pSEi0ZBQbFVB92g", "title": "ID card", "credentials": [{ "type": "file", "id": "VGVzdEZpbGVJRA",
            "name": "example-file.txt", "decryptedSize": 21, "integrityHash": "crWLSYO8T2f3yGaHQlDrMVvSvuu1YdXZewkjps422lQ" }] },
            { "id": "U9TPhd80SsWKKUtx3HxVsA", "title": "ID card", "credentials": [{ "type": "identity-document",
            "issuingCountry": { "fieldType": "country-code", "value": "US" }, "documentNumber": STRING(123456789),
            "identificationNumber": STRING(ID123456789) }] },
            { "id": "K4BBlNWWTS21ZqzTUn0H6Q", "title": "Passport", "credentials": [{ "type": "passport",
            "passportNumber": STRING(A12345678), "passportType": STRING(PP), "fullName": STRING(John Doe) }] },
            { "id": "LmInpZjdRwKIKZFdbBz19g", "title": "John Doe", "credentials": [{ "type": "person-name", "title": STRING(Dr.),
            "given": STRING(John), "surnamePrefix": STRING(van), "surname": STRING(Doe) }] },
            { "id": "TMrjj3uIRtitVmIpiwXmyg", "title": "API key", "credentials": [{ "type": "api-key",
            "key": { "fieldType": "concealed-string", "value": "AIzaSyAy", "label": "API Key" }, "keyType": STRING(Bearer),
            "url": STRING(https://api.example.com), "validFrom": DATE(2025-01-01) }] },
            { "id": "QtvgfXSgS8O6ukLNZZKMlw", "title": "Generated Password", "credentials": [{ "type": "generated-password",
            "password": "KozyS!cf#Nc9C799" }] }
        ] }] }
    """#

    private func read() throws -> VaultImportResult {
        var json = example.replacingOccurrences(of: "RSA_KEY", with: VaultImportFixtures.rsaPKCS8)
        for (macro, type) in [("CONCEALED", "concealed-string"), ("STRING", "string"), ("MONTH", "year-month"), ("DATE", "date")] {
            let pattern = try Regex("\(macro)\\(([^)]*)\\)")
            json = json.replacing(pattern) { Self.field(type, String($0.output[1].substring ?? "")) }
        }
        let data = Data(json.utf8)
        #expect(VaultImporter.format(of: data) == .cxf)
        return try VaultCXFReader.read(data)
    }

    @Test func `the example of the specification is imported`() throws {
        let result = try read()
        #expect(result.items.map(\.overview.title) == [
            "GitHub Login", "Visa Credit Card", "Wifi", "Home alarm", "Driver License", "House Address", "SSH Key", "ID card", "Passport",
            "John Doe", "API key", "Generated Password",
        ])
        #expect(result.items.map(\.overview.category) == [
            .login, .card, .custom, .note, .document, .identity, .sshKey, .document, .document, .identity, .custom, .login,
        ])
        #expect(result.issues == [
            VaultImportIssue(position: 2, title: "WebAuthn.io", reason: .passkey, isItemSkipped: true),
            VaultImportIssue(position: 9, title: "ID card", reason: .attachment, isItemSkipped: true),
        ])
    }

    @Test func `a login keeps its address, code, tags and collections`() throws {
        let github = try read().items[0]
        #expect(github.overview.urls == ["https://github.com"])
        #expect(github.overview.tags == ["development", "git", "Work Accounts"])
        #expect(github.overview.subtitle == "johndoe")
        #expect(github.details.createdAt == Date(timeIntervalSince1970: 1_705_142_400))
        #expect(github.overview.modifiedAt == nil)
        #expect(github.details.credential(VaultCredentialType.basicAuth)?.string("password") == "securepassword123")
        let totp = try #require(github.details.credential(VaultCredentialType.totp))
        #expect([totp.string("secret"), totp.string("algorithm"), totp.string("issuer")] == ["JBSWY3DPEHPK3PXP", "sha256", "GitHub"])
        #expect(totp.integer("digits") == 6)
    }

    @Test func `cards, documents and identities keep their keys`() throws {
        let items = try read().items
        let card = try #require(items[1].details.credential(VaultCredentialType.creditCard))
        #expect(card.string("number") == "4111111111111111")
        #expect(card.string("expiryDate") == "2027-08")
        #expect(card.string("pin") == "0000")
        let license = try #require(items[4].details.credential(VaultCredentialType.driversLicense))
        #expect(license.string("documentNumber") == "D12345678")
        #expect(license.string("issuingCountry") == "US")
        #expect(license.string("licenseClass") == "C")
        #expect(items[7].details.credential(VaultCredentialType.identityDocument)?.string("documentNumber") == "123456789")
        #expect(items[8].details.credential(VaultCredentialType.passport)?.string("documentNumber") == "A12345678")
        #expect(items[5].details.credential(VaultCredentialType.address)?.string("tel") == "+1-555-123-4567")
        #expect(items[9].details.credential(VaultCredentialType.personName)?.string("surnamePrefix") == "van")
        #expect(items[3].details.notes == "some instructionts to enable/disable the alarm")
        #expect(items[11].details.credential(VaultCredentialType.basicAuth)?.string("password") == "KozyS!cf#Nc9C799")
    }

    @Test func `other credential types become custom fields`() throws {
        let items = try read().items
        let wifi = items[2].details.fields.map { [$0.string("label"), $0.string("type"), $0.string("value")] }
        let expected = [
            ["hidden", "text", "false"], ["Security Type", "text", "wpa2-personal"], ["L", "concealed", "mypassword123"],
            ["L", "text", "Home_Network"],
        ]
        #expect(wifi == expected)
        #expect(items[10].details.fields.map { $0.string("type") } == ["concealed", "text", "text", "date"])
    }

    @Test func `an SSH key in PKCS#8 is turned into OpenSSH`() throws {
        let item = try read().items[6]
        let key = try #require(item.details.credential(VaultCredentialType.sshKey))
        #expect(key.string("keyType") == "ssh-rsa")
        #expect(key.string("keyComment") == "Work SSH Key")
        #expect(key.string("fingerprint") == VaultImportFixtures.rsaFingerprint)
        #expect(key.string("publicKey").hasPrefix(VaultImportFixtures.rsaPublicPrefix))
        #expect(key.string("publicKey").hasSuffix(" Work SSH Key"))
        #expect(key.string("creationDate") == "2023-01-01")
        let reread = try #require(VaultSSHKey(text: key.string("privateKey")))
        #expect(reread.pkcs8.map(VaultCXFSchema.base64URL) == VaultImportFixtures.rsaPKCS8)
    }

    @Test func `a newer major version, a strange code or another document is refused`() throws {
        let newer = #"{ "version": { "major": 2, "minor": 0 }, "accounts": [] }"#
        #expect(throws: VaultImportError.unsupportedVersion) { try VaultCXFReader.read(Data(newer.utf8)) }
        #expect(throws: VaultImportError.unknownFormat) { try VaultCXFReader.read(Data(#"{ "accounts": [] }"#.utf8)) }
        let md5 = #"""
        { "version": { "major": 1, "minor": 1 }, "accounts": [{ "items": [{ "title": "X", "credentials": [
            { "type": "totp", "secret": "JBSWY3DP", "period": 30, "digits": 6, "algorithm": "md5" },
            { "type": "basic-auth", "password": { "fieldType": "concealed-string", "value": "p" } },
            { "type": "item-reference", "reference": { "item": "abc" } }] }] }] }
        """#
        let result = try VaultCXFReader.read(Data(md5.utf8))
        #expect(result.items.count == 1)
        #expect(result.issues.map(\.reason) == [.invalidOneTimeCode, .unsupportedType("item-reference")])
    }
}
