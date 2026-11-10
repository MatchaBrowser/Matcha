import CryptoKit
import Foundation

/// OpenBSD's `bcrypt_pbkdf` (`lib/libutil/bcrypt_pbkdf.c`), the key derivation of OpenSSH's encrypted private keys
/// (kdf `bcrypt`): PBKDF2's structure with SHA-512 and, as its pseudorandom function, a bcrypt hash (EksBlowfish, cost 6,
/// over the hashed password and salt) of the fixed text “OxychromaticBlowfishSwatDynamite”. Output bytes are spread
/// across the blocks rather than taken in order, unlike PBKDF2. Checked against pyca/bcrypt's `kdf` and keys written by
/// `ssh-keygen`. Pure type.
nonisolated enum BcryptPBKDF {
    /// Size of a bcrypt hash: 8 words.
    private static let hashSize = 32
    private static let magic = Array("OxychromaticBlowfishSwatDynamite".utf8)

    /// `length` bytes derived from `password` and `salt` with `rounds` iterations; nil on parameters OpenBSD refuses
    /// (empty password or salt, no round, no byte or more than 1 024).
    static func derive(password: Data, salt: Data, rounds: Int, length: Int) -> Data? {
        guard rounds >= 1, !password.isEmpty, !salt.isEmpty, length > 0, length <= hashSize * hashSize else {
            return nil
        }
        let stride = (length + hashSize - 1) / hashSize
        let amount = (length + stride - 1) / stride
        let passwordHash = Array(SHA512.hash(data: password))
        let blowfish = Blowfish()
        var key = [UInt8](repeating: 0, count: length)
        for count in 1 ... stride {
            var saltHasher = SHA512()
            saltHasher.update(data: salt)
            saltHasher.update(data: withUnsafeBytes(of: UInt32(count).bigEndian) { Data($0) })
            var block = hash(password: passwordHash, salt: Array(saltHasher.finalize()), blowfish: blowfish)
            var output = block
            for _ in 1 ..< rounds {
                block = hash(password: passwordHash, salt: Array(SHA512.hash(data: block)), blowfish: blowfish)
                for index in 0 ..< hashSize {
                    output[index] ^= block[index]
                }
            }
            for index in 0 ..< amount {
                let destination = index * stride + count - 1
                guard destination < length else {
                    break
                }
                key[destination] = output[index]
            }
        }
        return Data(key)
    }

    /// `bcrypt_hash`: EksBlowfish keyed with the password and salt hashes (salted schedule, then 64 times the salt's
    /// and the password's), then the magic text encrypted 64 times; the 8 words come out little-endian.
    private static func hash(password: [UInt8], salt: [UInt8], blowfish: Blowfish) -> [UInt8] {
        blowfish.reset()
        blowfish.expand(key: password, data: salt)
        for _ in 0 ..< 64 {
            blowfish.expand(key: salt)
            blowfish.expand(key: password)
        }
        var position = 0
        var words = (0 ..< hashSize / 4).map { _ in Blowfish.word(of: magic, at: &position) }
        for _ in 0 ..< 64 {
            for pair in Swift.stride(from: 0, to: words.count, by: 2) {
                var left = words[pair]
                var right = words[pair + 1]
                blowfish.encipher(&left, &right)
                words[pair] = left
                words[pair + 1] = right
            }
        }
        return words.flatMap { word in (0 ..< 4).map { UInt8(truncatingIfNeeded: word &>> (8 * UInt32($0))) } }
    }
}
