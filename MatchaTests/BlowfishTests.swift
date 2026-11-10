import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// A Blowfish test vector, in hexadecimal.
private struct BlowfishVector: Sendable {
    let key: String
    let plaintext: String
    let ciphertext: String
}

/// A `bcrypt_pbkdf` test vector: password and salt in UTF-8, the expected key in hexadecimal.
private struct BcryptVector: Sendable {
    let password: String
    let salt: String
    let rounds: Int
    let key: String
}

/// Blowfish and OpenBSD's `bcrypt_pbkdf`, which decrypt OpenSSH keys (`VAULT.md` § 9.4): Eric Young's Blowfish vectors,
/// and `bcrypt_pbkdf` vectors computed by another implementation (pyca/bcrypt's `kdf`, in Rust).
struct BlowfishTests {
    private static func hex(_ text: String) -> [UInt8] {
        let digits = Array(text)
        return stride(from: 0, to: digits.count, by: 2).map { index in
            UInt8(String(digits[index ..< index + 2]), radix: 16) ?? 0
        }
    }

    @Test func `the initial state is pi's digits`() {
        let state = Blowfish.initialState
        #expect(state.count == Blowfish.wordCount)
        #expect([state[0], state[17], state[18], state[1041]] == [0x243F_6A88, 0x8979_FB1B, 0xD131_0BA6, 0x3AC3_72E6])
        // SHA-256 of the 1 042 words, big-endian, computed from pi's digits by another program.
        let bytes = state.flatMap { word in [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: word >> $0) } }
        let expected = "b5643208907b11b20e499a42187dc921f9579d28dadfccbe69a5ce232a55952f"
        #expect(Data(SHA256.hash(data: bytes)) == Data(Self.hex(expected)))
    }

    @Test(arguments: [
        BlowfishVector(key: "0000000000000000", plaintext: "0000000000000000", ciphertext: "4EF997456198DD78"),
        BlowfishVector(key: "FFFFFFFFFFFFFFFF", plaintext: "FFFFFFFFFFFFFFFF", ciphertext: "51866FD5B85ECB8A"),
        BlowfishVector(key: "3000000000000000", plaintext: "1000000000000001", ciphertext: "7D856F9A613063F2"),
        BlowfishVector(key: "0123456789ABCDEF", plaintext: "1111111111111111", ciphertext: "61F9C3802281B096"),
        BlowfishVector(key: "FEDCBA9876543210", plaintext: "0123456789ABCDEF", ciphertext: "0ACEAB0FC6A0A28D"),
        BlowfishVector(
            key: "F0E1D2C3B4A5968778695A4B3C2D1E0F0011223344556677",
            plaintext: "FEDCBA9876543210",
            ciphertext: "05044B62FA52D080",
        ),
    ])
    private func `a Blowfish block encrypts to the published ciphertext`(vector: BlowfishVector) {
        let block = Self.hex(vector.plaintext)
        var left = block[0 ..< 4].reduce(0) { ($0 << 8) | UInt32($1) }
        var right = block[4 ..< 8].reduce(0) { ($0 << 8) | UInt32($1) }
        Blowfish(key: Self.hex(vector.key)).encipher(&left, &right)
        #expect(String(format: "%08X%08X", left, right) == vector.ciphertext)
    }

    @Test(arguments: [
        BcryptVector(
            password: "password",
            salt: "salt",
            rounds: 4,
            key: "5bbf0cc293587f1c3635555c27796598d47e579071bf427e9d8fbe842aba34d9",
        ),
        BcryptVector(
            password: "password",
            salt: "salt",
            rounds: 4,
            key: "5ba4bfc60c7ac272931458407f4c1c4936ea356c55125c5a279b791d65bf9842"
                + "d49d7e1b572a9052715ebfa9421e7e949d8f8f19be3284732af1ba28341dd9bf",
        ),
        BcryptVector(password: "Café", salt: "salt", rounds: 2, key: "cea078b6f63c685b4d98d4a76b680f7f1878d1ee59b1b933302cc10c8592acdf22"),
        BcryptVector(password: "\0", salt: "\u{1}", rounds: 1, key: "6544cb60032b4b"),
    ])
    private func `bcrypt_pbkdf gives the reference values`(vector: BcryptVector) {
        let expected = Self.hex(vector.key)
        let derived = BcryptPBKDF.derive(
            password: Data(vector.password.utf8),
            salt: Data(vector.salt.utf8),
            rounds: vector.rounds,
            length: expected.count,
        )
        #expect(derived == Data(expected))
    }

    @Test func `bcrypt_pbkdf with ssh-keygen's parameters gives the reference value`() {
        // 16-byte salt, cost 16, key and IV of aes256-ctr.
        let derived = BcryptPBKDF.derive(password: Data("correct horse".utf8), salt: Data(0 ..< 16), rounds: 16, length: 48)
        let expected = "6bd628cd9202c5d0cb3e47dc1332be0162d3d4262dac8dac9f00998434479f36930c217fd05e33a7e77e207f680659d2"
        #expect(derived == Data(Self.hex(expected)))
    }

    @Test func `bcrypt_pbkdf refuses what OpenBSD refuses`() {
        let password = Data("password".utf8)
        let salt = Data("salt".utf8)
        #expect(BcryptPBKDF.derive(password: Data(), salt: salt, rounds: 4, length: 32) == nil)
        #expect(BcryptPBKDF.derive(password: password, salt: Data(), rounds: 4, length: 32) == nil)
        #expect(BcryptPBKDF.derive(password: password, salt: salt, rounds: 0, length: 32) == nil)
        #expect(BcryptPBKDF.derive(password: password, salt: salt, rounds: 4, length: 0) == nil)
        #expect(BcryptPBKDF.derive(password: password, salt: salt, rounds: 1, length: 1025) == nil)
    }
}
