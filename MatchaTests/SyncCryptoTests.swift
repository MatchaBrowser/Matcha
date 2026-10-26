import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// Sync encryption (task 7.5, `SYNC.md` § 3): RFC and NIST vectors, scheme vectors computed by another implementation
/// (Python `cryptography`), and rejection of any modified or moved content.
struct SyncCryptoTests {
    private let testKeychain = TestKeychain()
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

    private func bytes(_ range: Range<UInt8>) -> Data {
        Data(range)
    }

    private func raw(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    private func nonce(_ range: Range<UInt8>) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: bytes(range))
    }

    // MARK: Primitives

    @Test func `PBKDF2, HKDF and AES-GCM give the published values`() throws {
        // RFC 7914, § 11 (PBKDF2-HMAC-SHA256).
        let password = Data("password".utf8)
        let salt = Data("salt".utf8)
        #expect(try SyncCrypto
            .pbkdf2(password: password, salt: salt, iterations: 1) ==
            hex("120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"))
        #expect(try SyncCrypto
            .pbkdf2(password: password, salt: salt, iterations: 4096) ==
            hex("c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"))
        // RFC 5869, case 3 (empty salt, empty info): the first 32 bytes.
        let okm = SyncCrypto.subkey(of: SymmetricKey(data: Data(repeating: 0x0B, count: 22)), info: "")
        #expect(raw(okm) == hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d"))
        // NIST, GCM case 14: zero key and nonce, 16 zero bytes.
        let sealed = try SyncCrypto.seal(
            Data(count: 16),
            key: SymmetricKey(data: Data(count: 32)),
            aad: Data(),
            nonce: AES.GCM.Nonce(data: Data(count: 12)),
        )
        let nist = Data(count: 12) + hex("cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919")
        #expect(sealed == nist)
    }

    @Test func `padding hides the exact size`() throws {
        #expect(SyncCrypto.pad(Data(count: 255), toMultipleOf: 256).count == 256)
        #expect(SyncCrypto.pad(Data(count: 256), toMultipleOf: 256).count == 512)
        #expect(try SyncCrypto.unpad(SyncCrypto.pad(Data([1, 0, 0x80, 0]), toMultipleOf: 256)) == Data([1, 0, 0x80, 0]))
        #expect(throws: SyncCryptoError.unreadable) { try SyncCrypto.unpad(Data(count: 256)) }
        #expect(throws: SyncCryptoError.unreadable) { try SyncCrypto.unpad(Data([1, 2, 0])) }
    }

    // MARK: Matcha's scheme

    @Test func `the keys of an account match the reference vectors`() throws {
        let password = "Café crème, 2026 !"
        #expect(SyncPassword.normalized(password) == hex("43616665cc8120637265cc806d652c20323032362021"))
        let kdf = SyncKDF(algorithm: "pbkdf2-sha256", iterations: 600_000, salt: bytes(0 ..< 16))
        let keys = try SyncAccountKeys.passwordKeys(password: password, kdf: kdf)
        #expect(raw(keys.authKey) == hex("5181174923363be5cfc1ddd47761224fe7653b627bb8a16b9b56e44cbf3bb477"))
        #expect(raw(keys.wrapKey) == hex("ef4e8ca94c79a8831d0be6956954257ea820aae32daad637623c33d573978bbd"))

        let accountKey = SymmetricKey(data: bytes(32 ..< 64))
        #expect(raw(SyncAccountKeys.dataKey(accountKey: accountKey)) ==
            hex("681021aae32d4b8896879d3b68426f203ffe80a3505f4f88688e393b71c8da7c"))
        let wrapped = try #require(Data(base64Encoded: "ZGVmZ2hpamtsbW5vtSkcc3+EmMJgIoX82mvpDSrkO645VA8Tv2uuthfFNFVN2Rq2ZgR73kssLbiYmJgk"))
        #expect(try SyncCrypto
            .seal(bytes(32 ..< 64), key: keys.wrapKey, aad: SyncAccountKeys.accountKeyAAD, nonce: nonce(100 ..< 112)) == wrapped)
        #expect(try raw(SyncAccountKeys.unwrap(wrapped, with: keys.wrapKey)) == bytes(32 ..< 64))

        let recoveryKey = try #require(SyncRecoveryKey(bytes: bytes(64 ..< 84)))
        let recovery = SyncAccountKeys.recoveryKeys(recoveryKey)
        #expect(raw(recovery.authKey) == hex("e09957c068a62d3d182a3eb20567f6081ae9d5ad89034125ffc2376aad9b2ee0"))
        #expect(raw(recovery.wrapKey) == hex("c99ca23f11c93fad7ae8bfc65d45937f1d3ba0bbb9f47770d68dccc3c41ee275"))
        let recoveryWrapped =
            try #require(Data(base64Encoded: "cHFyc3R1dnd4eXp7s5N8UZFUOtzOSzjCwNalJVB4uWQ2w4/Y3OMaYjcFGDaG8ywQwJ9tnr7Xz4peNUdl"))
        #expect(try raw(SyncAccountKeys.unwrap(recoveryWrapped, with: recovery.wrapKey)) == bytes(32 ..< 64))
    }

    @Test func `the recovery key is written and read in Crockford base 32`() throws {
        let key = try #require(SyncRecoveryKey(bytes: bytes(64 ..< 84)))
        #expect(key.displayed == "810M-4GT4-8N34-EJ29-995M-RKAE-9X85-2MJK")
        #expect(SyncRecoveryKey(text: "810m 4gt4 8n34 ej29 995m rkae 9x85 2mjk") == key)
        #expect(SyncRecoveryKey(text: "8lOM-4GT4-8N34-EJ29-995M-RKAE-9X85-2MJK") ==
            SyncRecoveryKey(text: "810M-4GT4-8N34-EJ29-995M-RKAE-9X85-2MJK"))
        #expect(SyncRecoveryKey(text: "810M-4GT4-8N34") == nil)
        #expect(SyncRecoveryKey(text: "810M-4GT4-8N34-EJ29-995M-RKAE-9X85-2MJU") == nil)
        let random = SyncRecoveryKey.random()
        #expect(SyncRecoveryKey(text: random.displayed) == random)
    }

    @Test func `a record is sealed to its identifier and refused anywhere else`() throws {
        let dataKey = SymmetricKey(data: hex("681021aae32d4b8896879d3b68426f203ffe80a3505f4f88688e393b71c8da7c"))
        let id = try #require(UUID(uuidString: "7C4B2E9A-1D3F-4B6E-8A0C-5E2D9F1B3A76"))
        let start = #"{"deleted":false,"fields":{"name":"Personnel","order":0},"modifiedAt":"2026-10-17T08:30:12.345Z","#
        let end = #""modifiedBy":"3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10","schema":1,"type":"profile"}"#
        let content = Data((start + end).utf8)
        let expected = """
        AXx9fn+AgYKDhIWGhy4GlMRzc+YJeTnjZErem3VDPTwk4WRTSxyMJDg2dKkUu4uAoKOZt3k+uh7IcGj4HGY2C4227yL/t64q\
        qc7gcBc4I8Nl/V1fUWESR9zeh72w6IDlRn8EZRMvtIEJCzt7F59kiu0eaWbgjf4rFD76riMiHHt/87v3+llWYu1G0aOXCi+/\
        smVS94aTfQOi+AmaSeEP+nb3zuE6/IfBEG6SrlO4rHaAljgF50eyLRxUKdDRS6bER/9J48TEGAtO5IZxFYAUESyey9ikCWO3\
        hnFvY/0XIyfSmOZ4aoeZmy3jPGSW6LeHhrsoAc/XdAXlRa8H6KRE2DBHSTqF0rVRlvVOweBtG/adxKH7kcFuGRDgEA1p
        """
        let payload = try SyncCrypto.encryptRecord(content, id: id, keyVersion: 1, dataKey: dataKey, nonce: nonce(124 ..< 136))
        #expect(payload == expected)
        let size = 1 + 12 + 256 + 16
        #expect(Data(base64Encoded: payload)?.count == size)
        #expect(try SyncCrypto.decryptRecord(payload, id: id, keyVersion: 1, dataKey: dataKey) == content)

        var tampered = try #require(Data(base64Encoded: payload))
        tampered[40] ^= 1
        var otherVersion = try #require(Data(base64Encoded: payload))
        otherVersion[0] = 2
        let refused: [() throws -> Data] = [
            { try SyncCrypto.decryptRecord(tampered.base64EncodedString(), id: id, keyVersion: 1, dataKey: dataKey) },
            { try SyncCrypto.decryptRecord(payload, id: UUID(), keyVersion: 1, dataKey: dataKey) },
            { try SyncCrypto.decryptRecord(payload, id: id, keyVersion: 2, dataKey: dataKey) },
            { try SyncCrypto.decryptRecord(otherVersion.base64EncodedString(), id: id, keyVersion: 1, dataKey: dataKey) },
            { try SyncCrypto.decryptRecord(payload, id: id, keyVersion: 1, dataKey: SymmetricKey(size: .bits256)) },
            { try SyncCrypto.decryptRecord("pas du base 64", id: id, keyVersion: 1, dataKey: dataKey) },
        ]
        for attempt in refused {
            #expect(throws: SyncCryptoError.unreadable) { try attempt() }
        }
    }

    @Test func `an extension package is sealed with its own key`() throws {
        let key = SymmetricKey(data: bytes(150 ..< 182))
        let id = try #require(UUID(uuidString: "5A1C9E3B-7D2F-4B8A-9C6E-1F0D3B7A2E58"))
        var package = Data([0x50, 0x4B, 0x03, 0x04])
        for _ in 0 ..< 4 {
            package.append(Data(0 ... 255))
        }
        let sealed = try SyncCrypto.encryptBlob(package, id: id, key: key, nonce: nonce(136 ..< 148))
        #expect(sealed.count == 1 + 12 + SyncCrypto.blobPadding + 16)
        #expect(SHA256.hash(data: sealed).map { String(format: "%02x", $0) }
            .joined() == "21c61a10b905ebc08287797aac0bf30e30134f9f21af66e71ccb185e492f4a85")
        #expect(try SyncCrypto.decryptBlob(sealed, id: id, key: key) == package)
        #expect(throws: SyncCryptoError.unreadable) { try SyncCrypto.decryptBlob(sealed, id: UUID(), key: key) }
    }

    // MARK: Account

    @Test func `weak passwords and parameters are refused`() {
        let kdf = SyncKDF.random()
        #expect(throws: SyncCryptoError.passwordTooShort) { try SyncAccountKeys.passwordKeys(password: "court", kdf: kdf) }
        var weak = kdf
        weak.iterations = 100_000
        #expect(throws: SyncCryptoError.weakKDF) { try SyncAccountKeys.passwordKeys(password: "assez long pour passer", kdf: weak) }
        var other = kdf
        other.algorithm = "argon2id"
        #expect(throws: SyncCryptoError.weakKDF) { try SyncAccountKeys.passwordKeys(password: "assez long pour passer", kdf: other) }
        #expect(kdf.salt.count == 16 && kdf.salt != SyncKDF.random().salt)
    }

    @Test func `a new account opens with its password or its recovery key`() throws {
        let password = "un mot de passe bien long"
        let creation = try SyncAccountKeys.creation(password: password)
        let login = try SyncAccountKeys.passwordKeys(password: password, kdf: creation.kdf)
        #expect(raw(login.authKey) == creation.authKey)
        #expect(try raw(SyncAccountKeys.unwrap(creation.wrappedAccountKey, with: login.wrapKey)) == raw(creation.accountKey))

        let typed = try #require(SyncRecoveryKey(text: creation.recoveryKey.displayed.lowercased()))
        let recovery = SyncAccountKeys.recoveryKeys(typed)
        #expect(raw(recovery.authKey) == creation.recoveryAuthKey)
        #expect(try raw(SyncAccountKeys.unwrap(creation.recoveryWrappedAccountKey, with: recovery.wrapKey)) == raw(creation.accountKey))

        let wrongPassword = try SyncAccountKeys.passwordKeys(password: "un autre mot de passe long", kdf: creation.kdf)
        #expect(throws: SyncCryptoError.unreadable) { try SyncAccountKeys.unwrap(creation.wrappedAccountKey, with: wrongPassword.wrapKey) }
    }

    @Test func `the account's avatar is sealed to the account, as the server's client does`() throws {
        let dataKey = SymmetricKey(data: bytes(0 ..< 32))
        let account = try #require(UUID(uuidString: "5D0C7A3E-2B1F-4E8D-9A6C-0F3B7E1D2C54"))
        let picture = Data([0x89, 0x50, 0x4E, 0x47]) + bytes(0 ..< 255) + Data([255])
        let sealed = try SyncCrypto.encryptAvatar(picture, accountID: account, keyVersion: 1, dataKey: dataKey, nonce: nonce(200 ..< 212))
        // Computed by the reference server's test client (`internal/testclient`, EncryptAvatar).
        #expect(sealed.count == 4125)
        #expect(SHA256.hash(data: sealed).map { String(format: "%02x", $0) }.joined()
            == "f38d815522dc01acc145c303107dac400055c33c14ef3453279a09aaf19ca36e")
        #expect(try SyncCrypto.decryptAvatar(sealed, accountID: account, keyVersion: 1, dataKey: dataKey) == picture)
        #expect(throws: SyncCryptoError.unreadable) {
            try SyncCrypto.decryptAvatar(sealed, accountID: UUID(), keyVersion: 1, dataKey: dataKey)
        }
    }

    @Test func `the keychain keeps the account key by server and by account`() throws {
        let keychain = testKeychain.make()
        let server = SyncServerAddress(normalized: "https://sync.example.com/api")
        let other = SyncServerAddress(normalized: "https://other.example.com")
        let account = UUID()
        defer {
            keychain.removeAccount(server: server, accountID: account)
            keychain.removeAccount(server: other, accountID: account)
        }
        #expect(try keychain.data(for: .accountKey, server: server, accountID: account) == nil)
        try keychain.set(Data([1, 2, 3]), for: .accountKey, server: server, accountID: account)
        try keychain.set(Data([4, 5, 6]), for: .accountKey, server: server, accountID: account)
        #expect(try keychain.data(for: .accountKey, server: server, accountID: account) == Data([4, 5, 6]))
        #expect(try keychain.data(for: .accountKey, server: other, accountID: account) == nil)
        keychain.removeAccount(server: server, accountID: account, items: [.accountKey])
        #expect(try keychain.data(for: .accountKey, server: server, accountID: account) == nil)
        #expect(SyncKeychain.name(of: .refreshToken, server: server, accountID: account).hasPrefix("https://sync.example.com/api|"))
    }

    /// Read here by the test host, whose sandbox has wider exceptions than the published app's (review DI8): the app's
    /// own reading is checked by hand, on the image of scripts/package.sh (TESTS_MANUELS.md).
    @Test func `this machine has a stable mark`() {
        let mark = SyncMachineMark.current()
        #expect(mark?.count == 64)
        #expect(mark == SyncMachineMark.current())
    }
}
