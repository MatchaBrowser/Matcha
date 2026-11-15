import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// Encryption of the vault (`VAULT.md` § 2 to § 6): the vectors of § 12, computed by another implementation (Python
/// `cryptography`), and the rejection of a part moved to another item, vault or role.
struct VaultCryptoTests {
    private static let wrapKey = "61399e6410861ea6bd2318e9e8b5d39d5027c31e523594d6646f8d7bc8743319"
    private static let recoveryWrapKey = "c99ca23f11c93fad7ae8bfc65d45937f1d3ba0bbb9f47770d68dccc3c41ee275"
    private static let idKey = "1566d83727cc0f51bd6130bcfbeb63b5edeed74d0aa752c98507d8610a539dac"
    private static let device = "3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10"
    private static let itemID = "0F8C2A6E-5B3D-4E7A-9C1F-2D6B8E4A7C30"
    private static let overview = #"{"category":"login","favorite":false,"match":"site","modifiedAt":"2026-11-08T09:15:00.000Z","#
        + #""modifiedBy":"3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10","subtitle":"jeremy","tags":["dev"],"title":"GitHub","#
        + #""trashedAt":null,"urls":["https://github.com/login"]}"#
    private static let details = #"{"createdAt":"2026-11-08T09:15:00.000Z","credentials":[{"id":"C1","#
        + #""password":"correct horse battery staple","type":"basic-auth","username":"jeremy"},{"algorithm":"sha1","#
        + #""digits":6,"id":"C2","issuer":"GitHub","period":30,"secret":"JBSWY3DPEHPK3PXP","type":"totp"}],"#
        + #""fields":[],"files":[],"history":[],"notes":""}"#
    private static let overviewField = "AaSkpKSkpKSkpKSkpJTImjZEfuEDI9mXbunaMltEPJY2/aq0qzHS6ZE5EpB5Q2wq82wtAGXM4xTXcvHg9l07GEsCt6sC8BXF"
        + "wvN4tSZeeDuBoLQ8fvPnM1Tc/UTmgA6nfkatLW3hLhkMFt/XDgGRLqBrIYKcoHf6kst5tAm6nuaXUKBpr3Q8Z9LyYT9JeHjx"
        + "9cvdR3YemdhgLjARp3tOF2wYW/uu0y+lJE7c7qPdE4tKt2wY2lCMvSOd8U71b/KS1+akOg/MIJ+gmJk07Qfo6fdN1pXZ/Aov"
        + "OL4AEgzh9ihxLcS9Nnmb7RZpCmGwWr6GYn1gXXDTiQ0HiqgZJdOtwQZqOmYssXhYg+LMl7L3N/o6U3GsFjmumIOrTxaA"
    private static let bucketField = "Aaampqampqampqampv20zjnk5BEolTd57Py/IIEQJqx0M3d5dmamU4DybL4A5lCeqpXZJONfTELyEBiWAkBn9VQwbt/kYEeA"
        + "6Jc0lwcOO/eSWe2ZI0JunA5BatHVlllBgCc/UVpnH20pgxICeSRNLNCq9ECAromaQzHzF9wE2+a8Rh0BmDwy/eVyYaiZNLgt"
        + "lh7cFmFITBUr3nT5/D6bljDXEvrHEigAJOBpo/UqbnXkK1fFrLeRZNpGV/Kw2wIATMOGTWt9/Z5KnxydIhHnzkooGSGteNLx"
        + "ZDTRSIndyAHcQS5jwxvnQaigJcm7BeSmbB1IxzW5umpQEv37TEbKDYYi8OGa8QNY6inHbli208UZUFkxmhelm/NDWh9j"
    private static let rootField = "Aaenp6enp6enp6enpzr7aWaj5an1/5ZxtXyOkuFsZC0f4+urNSyZxd3QrkD8f401pDR8ZBdIP7KNV5H5LP+0LH2Zs4EdKz9U"
        + "Zl/t1liEzGSJG8Y3FBj2//d/K+/awVYJmLRyFwVD0MRhtidF7oF7EpDnr1Yfuo5HmveAqU4TgyDz0Z60uCkvdbvrQsaXK5DA"
        + "qDUBc/to98qdN2aC8+eUj8Jmh0yietWJtCH+UfYWPQBHcWtC+vosjvYL7OD7FGYJKbPAZIHUvHx/QYPV16yPLVs3oIR6kzYz"
        + "C3xVO8zk9QjDfAezGTLZFAJEZj5aJ3kEQf4Q604UBLNmOE0rvUOeHGnqrnQdGKx+Rn2X4XZSftBt0+GEYJkx1oWGsw8f"

    private func hex(_ text: String) -> Data {
        var data = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            data.append(UInt8(text[index ..< next], radix: 16) ?? 0)
            index = next
        }
        return data
    }

    private func raw(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private func nonce(_ byte: UInt8) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: Data(repeating: byte, count: 12))
    }

    private var vaultRootKey: SymmetricKey {
        SymmetricKey(data: Data(208 ... 239))
    }

    private var keys: VaultCrypto.Keys {
        VaultCrypto.Keys(vaultRootKey: vaultRootKey)
    }

    private func address() throws -> VaultCrypto.Address {
        try VaultCrypto.Address(vaultID: keys.vaultID, itemID: #require(UUID(uuidString: Self.itemID)))
    }

    private func sealedItem() throws -> VaultSealedItem {
        try VaultCrypto.sealItem(
            overview: Data(Self.overview.utf8),
            details: Data(Self.details.utf8),
            itemKey: SymmetricKey(data: Data(repeating: 0x11, count: 32)),
            at: address(),
            keys: keys,
            nonces: VaultCrypto.Nonces(itemKey: nonce(0xA3), overview: nonce(0xA4), details: nonce(0xA5)),
        )
    }

    @Test func `the envelopes and keys of the vault give the vectors`() throws {
        let wrapKey = SymmetricKey(data: hex(Self.wrapKey))
        let wrapped = try VaultCrypto.wrapRootKey(vaultRootKey, with: wrapKey, nonce: nonce(0xA1))
        #expect(wrapped.base64EncodedString() == "oaGhoaGhoaGhoaGhEOxauvt9iwApCVrUiHK62nCeXEyW8TvEbI8xQnr0mK1RKoY25LICmBnLMoj46sw+")
        let recovery = try VaultCrypto.wrapRootKey(vaultRootKey, with: SymmetricKey(data: hex(Self.recoveryWrapKey)), nonce: nonce(0xA2))
        #expect(recovery.base64EncodedString() == "oqKioqKioqKioqKi/O/doW8QrILBadMk0oZpdE7H+MfGYVN1ydlMb/xNojP0DQpiSgDsZGGd4pyRvBoi")
        #expect(try raw(VaultCrypto.unwrapRootKey(wrapped, with: wrapKey)) == raw(vaultRootKey))
        // Not the envelope of the account key, nor under another key.
        #expect(throws: SyncCryptoError.self) { try SyncAccountKeys.unwrap(wrapped, with: wrapKey) }
        #expect(throws: SyncCryptoError.self) { try VaultCrypto.unwrapRootKey(wrapped, with: SymmetricKey(size: .bits256)) }

        #expect(raw(keys.vault) == hex("8261db72fb9ebf224e624f04aa9d445a64aaac04ac53f8e9668f3c67e93dd6de"))
        #expect(raw(keys.itemWrap) == hex("a66570248ec1e58cf77e60053367b6a8163f92d4960ad6aa18e5f3baf2fffbce"))
        #expect(raw(keys.manifest) == hex("2358b6d07fdec265ec600aff1e6a4923395e279705b34b348ece7c92a9dd69af"))
        #expect(keys.vaultID.uuidString == "02AFD736-3BA5-8284-BE72-68DCE1F17671")
        let identifiers = SyncIdentifiers(idKey: SymmetricKey(data: hex(Self.idKey)))
        #expect(identifiers.vaultManifest(of: keys.vaultID).uuidString == "12FFDC1F-CB5A-851F-A0E8-FF1D5482C62D")
        #expect(identifiers.vaultBucket("0", of: keys.vaultID).uuidString == "F16781CF-1918-8D31-9C78-8D9F12E85B96")
    }

    @Test func `an item gives the vectors and opens only where it was sealed`() throws {
        let item = try sealedItem()
        #expect(try String(bytes: address().aad(.itemKey), encoding: .utf8)
            == "matcha.vault.item-key.v1|02afd736-3ba5-8284-be72-68dce1f17671|0f8c2a6e-5b3d-4e7a-9c1f-2d6b8e4a7c30|1")
        #expect(item.itemKey
            .base64EncodedString() == "AaOjo6Ojo6Ojo6Ojo5B41srfBJztsNM+eH4hy0i/PDDMhFs/U9zzWqtC7AOpTsibBHGeJtXBEqCrGI9kCQ==")
        #expect(item.overview.base64EncodedString() == Self.overviewField)
        #expect(item.details.count == 1053)
        #expect(SHA256.hash(data: item.details).hexString == "dd6959378ff61c404dc6a03ea42870e400f294607ca0876abffaae8d1d56c555")
        #expect(item.digest == "cf16a0a026abc5e2824ef98804918c1ed1951800859bbc7a1d835978dc240665")

        let itemKey = try VaultCrypto.openItemKey(of: item, at: address(), keys: keys)
        #expect(try VaultCrypto.openOverview(of: item, itemKey: itemKey, at: address()) == Data(Self.overview.utf8))
        #expect(try VaultCrypto.openDetails(of: item, itemKey: itemKey, at: address()) == Data(Self.details.utf8))

        let other = VaultCrypto.Address(vaultID: keys.vaultID, itemID: UUID())
        #expect(throws: SyncCryptoError.self) { try VaultCrypto.openItemKey(of: item, at: other, keys: keys) }
        let otherVault = try VaultCrypto.Address(vaultID: UUID(), itemID: #require(UUID(uuidString: Self.itemID)))
        #expect(throws: SyncCryptoError.self) { try VaultCrypto.openItemKey(of: item, at: otherVault, keys: keys) }
        let swapped = VaultSealedItem(itemKey: item.itemKey, overview: item.details, details: item.overview)
        #expect(throws: SyncCryptoError.self) { try VaultCrypto.openOverview(of: swapped, itemKey: itemKey, at: address()) }
        #expect(throws: SyncCryptoError.self) { try VaultCrypto.openItemKey(
            of: item,
            at: address(),
            keys: VaultCrypto.Keys(vaultRootKey: SymmetricKey(size: .bits256)),
        ) }
    }

    @Test func `the manifest gives the vectors`() throws {
        let vaultID = keys.vaultID
        let tombstone = try #require(SyncCoding.date(from: "2026-11-01T10:00:00.000Z"))
        let bucket = try VaultBucket(
            deleted: ["5c1d9e7a-2b4f-4a6c-8e0d-1f3b5a7c9e2d": tombstone],
            items: [Self.itemID.lowercased(): sealedItem().digest],
        )
        let sealedBucket = try VaultManifestCrypto.sealBucket(bucket, named: "0", vaultID: vaultID, keys: keys, nonce: nonce(0xA6))
        #expect(sealedBucket.base64EncodedString() == Self.bucketField)
        #expect(VaultManifestCrypto.bucketDigest(sealedBucket) == "68af6b3fc517a14fb9b0ec35e8407651e3cc513d97f064ec9441af472ab9fafc")
        #expect(try VaultManifestCrypto.openBucket(sealedBucket, named: "0", vaultID: vaultID, keys: keys) == bucket)
        #expect(throws: SyncCryptoError.self) { try VaultManifestCrypto.openBucket(sealedBucket, named: "1", vaultID: vaultID, keys: keys) }

        let root = VaultRoot(
            buckets: ["0": VaultManifestCrypto.bucketDigest(sealedBucket)],
            clock: [Self.device.lowercased(): 1],
            modifiedAt: SyncCoding.date(from: "2026-11-08T09:15:00.000Z"),
            modifiedBy: UUID(uuidString: Self.device),
        )
        let sealedRoot = try VaultManifestCrypto.sealRoot(root, vaultID: vaultID, keys: keys, nonce: nonce(0xA7))
        #expect(sealedRoot.base64EncodedString() == Self.rootField)
        #expect(try VaultManifestCrypto.openRoot(sealedRoot, vaultID: vaultID, keys: keys) == root)
        #expect(throws: SyncCryptoError.self) { try VaultManifestCrypto.openRoot(sealedBucket, vaultID: vaultID, keys: keys) }
    }

    @Test func `a root succeeds another only if its clock covers it`() {
        let first = "a", second = "b"
        let base = VaultRoot(clock: [first: 2, second: 1])
        #expect(VaultRoot(clock: [first: 2, second: 1]).succeeds(base))
        #expect(VaultRoot(clock: [first: 3, second: 1]).succeeds(base))
        #expect(VaultRoot(clock: [first: 2, second: 1, "c": 1]).succeeds(base))
        #expect(!VaultRoot(clock: [first: 1, second: 5]).succeeds(base))
        #expect(!VaultRoot(clock: [first: 2]).succeeds(base))
        #expect(base.mergedClock(with: VaultRoot(clock: [first: 1, second: 4])) == [first: 2, second: 4])
        let device = UUID()
        #expect(base.clock(ofWriteBy: device)[device.uuidString.lowercased()] == 1)
    }

    @Test func `the details are padded with Padmé, from 1 KiB`() {
        let cases = [0: 1024, 1023: 1024, 1024: 1088, 1500: 1536, 5000: 5120, 20000: 20480, 70000: 71680]
        for (length, padded) in cases {
            #expect(VaultCrypto.padDetails(Data(count: length)).count == padded)
        }
        #expect(VaultCrypto.padme(1) == 1)
        #expect(VaultCrypto.padme(3) == 3)
    }

    @Test func `a file chunk gives the vector and opens only at its place`() throws {
        let content = Data(String(repeating: "Matcha vault file\n", count: 100).utf8)
        #expect(SHA256.hash(data: content).hexString == "5b499b55ca0b253aab15898936a55e6d66fd062726a394455c682c803d768d43")
        let fileID = try #require(UUID(uuidString: "3B9E1C4A-7D2F-4E8B-A6C0-5F1D2E3A4B59"))
        let key = SymmetricKey(data: Data(repeating: 0x22, count: 32))
        let chunk = try VaultManifestCrypto.encryptFileChunk(content, fileID: fileID, index: 0, count: 1, key: key, nonce: nonce(0xA8))
        #expect(chunk.count == 65565)
        #expect(SHA256.hash(data: chunk).hexString == "6bcc43e4c2969c2db20d701bd625b3637ac1debd9483c8ee44007d5d5641296d")
        #expect(try VaultManifestCrypto.decryptFileChunk(chunk, fileID: fileID, index: 0, count: 1, key: key) == content)
        #expect(throws: SyncCryptoError.self) {
            try VaultManifestCrypto.decryptFileChunk(chunk, fileID: fileID, index: 0, count: 2, key: key)
        }
        #expect(VaultManifestCrypto.chunkCount(ofSize: 0) == 1)
        #expect(VaultManifestCrypto.chunkCount(ofSize: VaultManifestCrypto.fileChunkBytes) == 1)
        #expect(VaultManifestCrypto.chunkCount(ofSize: VaultManifestCrypto.fileChunkBytes + 1) == 2)
    }
}
