import Foundation
@testable import Matcha
import Testing

/// Export as CXF (`VAULT.md` § 10), and the way back: what the vault holds comes back from its own export.
struct VaultCXFWriterTests {
    private func item(_ category: VaultCategory, _ title: String, _ build: (inout VaultImportDraft) -> Void) -> VaultItemContent {
        var draft = VaultImportDraft(position: 1, title: title, category: category)
        build(&draft)
        return draft.finished().content
    }

    private var items: [VaultItemContent] {
        [
            item(.login, "GitHub") { draft in
                draft.addURL("https://github.com/login")
                draft.addTag("dev")
                draft.content.overview.favorite = true
                draft.content.overview.match = .host
                draft.content.details.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
                draft.addCredential(VaultCredentialType.basicAuth, ["username": "jeremy", "password": "s3cret/é"])
                draft.addCredential(VaultOTPAuth.Setup(secret: "JBSWY3DPEHPK3PXP", algorithm: "sha512", digits: 8, period: 60, issuer: "GH")
                    .credential ?? VaultEntry())
                draft.addField(label: "PIN", type: .concealed, value: "1234")
                draft.addField(label: "Site", type: .url, value: "https://example.com")
                draft.addField(label: "Phone", type: .phone, value: "+33 1 23")
                draft.addField(label: "Backup", type: .totp, value: "otpauth://totp/?secret=KRSXG5A")
                draft.addField(label: "Mail", type: .email, value: "j@example.com")
                draft.addField(label: "Since", type: .date, value: "2020-01-02")
                draft.addNotes("first line\nsecond line")
            },
            item(.card, "Visa") { draft in
                draft.addCredential(VaultCredentialType.creditCard, [
                    "number": "4242424242424242", "fullName": "Jane Doe", "cardType": "Visa", "verificationNumber": "123",
                    "expiryDate": "2027-08", "pin": "0000",
                ])
            },
            item(.note, "Alarm") { $0.addNotes("4321") },
            item(.document, "Passport") { draft in
                let values = ["documentNumber": "A123", "issuingCountry": "FR", "expiryDate": "2030-01-01"]
                draft.addCredential(VaultCredentialType.passport, values)
            },
            item(.identity, "Me") { draft in
                draft.addCredential(VaultCredentialType.personName, ["given": "Jane", "surname": "Doe"])
                draft.addField(label: "Email", type: .email, value: "jane@example.com")
            },
            item(.sshKey, "Laptop") { $0.addSSHKey(privateKey: VaultImportFixtures.ed25519OpenSSH) },
            item(.custom, "Wi-Fi") { $0.addField(label: "SSID", type: .text, value: "home") },
        ]
    }

    @Test func `items come back from their own CXF export`() throws {
        var source = items
        source[0].details.files = [VaultEntry(["id": .string("F1"), "name": .string("scan.pdf")])]
        let export = try VaultCXFWriter.export(source)
        #expect(export.omittedFiles == 1)
        let result = try VaultCXFReader.read(export.data)
        #expect(result.issues.isEmpty)
        let back = result.items
        #expect(back.map(\.overview.title) == source.map(\.overview.title))
        #expect(back.map(\.overview.category) == source.map(\.overview.category))
        #expect(back.map(\.overview.urls) == source.map(\.overview.urls))
        #expect(back.map(\.overview.tags) == source.map(\.overview.tags))
        #expect(back.map(\.overview.subtitle) == source.map(\.overview.subtitle))
        #expect(back.map(\.details.notes) == source.map(\.details.notes))
        #expect(back[0].overview.favorite)
        #expect(back[0].overview.match == .host)
        #expect(back[0].details.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(back[0].details.files.isEmpty)
        // Credentials and fields keep their values; their identifiers are new, and an SSH key is written again.
        let strip = { (entries: [VaultEntry]) in
            entries.map { entry in entry.keys.filter { $0 != "id" && $0 != "privateKey" }.map { "\($0)=\(entry.value($0) ?? .null)" } }
        }
        for (original, copy) in zip(source, back) {
            #expect(strip(copy.details.credentials) == strip(original.details.credentials))
            #expect(strip(copy.details.fields) == strip(original.details.fields))
        }
        let key = back[5].details.credential(VaultCredentialType.sshKey)?.string("privateKey") ?? ""
        #expect(VaultSSHKey(text: key) == VaultSSHKey(text: VaultImportFixtures.ed25519OpenSSH))
    }

    @Test func `the document follows CXF`() throws {
        let export = try VaultCXFWriter.export(items, at: Date(timeIntervalSince1970: 1_705_228_800.7))
        let text = try #require(String(data: export.data, encoding: .utf8))
        #expect(!text.contains("\\/"))
        #expect(text.contains(#""exporterRpId":"matchabrowser.com""#))
        #expect(text.contains(#""timestamp":1705228800,"#))
        let json = try VaultImportJSON(data: export.data)
        #expect(json["version"]["major"].integer == 1)
        let account = json["accounts"].array[0]
        #expect(account["collections"].isArray)
        let github = account["items"].array[0]
        #expect(VaultCXFSchema.data(base64URL: github["id"].string)?.count == 16)
        #expect(github["scope"]["androidApps"].isArray)
        let types = github["credentials"].array.map { $0["type"].string }
        #expect(types == ["basic-auth", "totp", "custom-fields", "note"])
        let login = github["credentials"].array[0]
        #expect(login["password"]["fieldType"].string == "concealed-string")
        #expect(github["credentials"].array[1]["digits"].integer == 8)
        // Optional arrays are left out when empty.
        let note = account["items"].array[2]
        #expect(note["tags"].isNull)
        #expect(note["scope"].isNull)
        let passport = account["items"].array[3]["credentials"].array[0]
        #expect(passport["passportNumber"]["value"].string == "A123")
        #expect(passport["issuingCountry"]["fieldType"].string == "country-code")
        let key = account["items"].array[5]["credentials"].array[0]
        #expect(key["privateKey"].string == VaultCXFSchema.base64URL(VaultImportFixtures.base64(VaultImportFixtures.ed25519PKCS8)))
        #expect(key["keyComment"].string == "test@ed25519")
    }

    @Test func `an SSH key that can't be written in PKCS#8 is kept as custom fields`() throws {
        let unreadable = item(.sshKey, "Old key") { draft in
            let dsa = "-----BEGIN DSA PRIVATE KEY-----\nAAAA\n-----END DSA PRIVATE KEY-----"
            draft.addCredential(VaultCredentialType.sshKey, ["privateKey": dsa])
        }
        let back = try VaultCXFReader.read(VaultCXFWriter.export([unreadable]).data).items
        #expect(back.first?.details.fields.first?.string("type") == "concealed")
        #expect(back.first?.details.fields.first?.string("value").hasPrefix("-----BEGIN DSA") == true)
    }
}
