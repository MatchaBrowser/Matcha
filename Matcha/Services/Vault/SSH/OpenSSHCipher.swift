import CommonCrypto
import CryptoKit
import Foundation

/// A cipher of OpenSSH's encrypted private keys, for decryption: AES in CTR mode (`aes256-ctr`, `ssh-keygen`'s
/// default), CBC or GCM, with 128, 192 or 256-bit keys, through CommonCrypto (CTR, CBC) and CryptoKit (GCM). The key
/// and the IV come from the passphrase (`BcryptPBKDF`). Pure type.
nonisolated struct OpenSSHCipher: Equatable {
    enum Mode: Equatable {
        case none
        case ctr
        case cbc
        /// `aes…-gcm@openssh.com`: a 12-byte nonce, and a 16-byte tag after the encrypted section.
        case gcm
    }

    let mode: Mode
    let keySize: Int

    /// The cipher named `name` in the file; nil if Matcha doesn't have it (`chacha20-poly1305@openssh.com`, `3des-cbc`).
    init?(name: String) {
        let modes: [String: Mode] = ["ctr": .ctr, "cbc": .cbc, "gcm@openssh.com": .gcm]
        let sizes: [String: Int] = ["aes128": 16, "aes192": 24, "aes256": 32]
        guard name != "none" else {
            mode = .none
            keySize = 0
            return
        }
        let parts = name.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, let size = sizes[parts[0]], let mode = modes[parts[1]], mode != .gcm || size != 24 else {
            return nil
        }
        self.mode = mode
        keySize = size
    }

    var ivSize: Int {
        switch mode {
        case .none: 0
        case .ctr, .cbc: 16
        case .gcm: 12
        }
    }

    /// The encrypted section is a multiple of this size.
    var blockSize: Int {
        mode == .none ? OpenSSHKeyWriter.unencryptedBlockSize : 16
    }

    /// Size of the authentication tag that follows the encrypted section.
    var tagSize: Int {
        mode == .gcm ? 16 : 0
    }

    /// `data` decrypted. A GCM tag that doesn't match means a wrong passphrase; with CTR and CBC, the check numbers of
    /// the decrypted section tell (`OpenSSHKeyReader`).
    func decrypt(_ data: [UInt8], key: [UInt8], initializationVector: [UInt8], tag: [UInt8]) throws(SSHKeyError) -> [UInt8] {
        switch mode {
        case .none:
            return data
        case .gcm:
            guard let box = try? AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: initializationVector), ciphertext: data, tag: tag),
                  let plaintext = try? AES.GCM.open(box, using: SymmetricKey(data: key))
            else {
                throw .wrongPassphrase
            }
            return Array(plaintext)
        case .ctr, .cbc:
            return try decryptWithCommonCrypto(data, key: key, initializationVector: initializationVector)
        }
    }

    /// AES-CTR (big-endian 128-bit counter, as OpenSSH) or AES-CBC without padding.
    private func decryptWithCommonCrypto(_ data: [UInt8], key: [UInt8], initializationVector: [UInt8]) throws(SSHKeyError) -> [UInt8] {
        var cryptor: CCCryptorRef?
        let created = CCCryptorCreateWithMode(
            CCOperation(kCCDecrypt),
            CCMode(mode == .ctr ? kCCModeCTR : kCCModeCBC),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            initializationVector,
            key,
            key.count,
            nil,
            0,
            0,
            CCModeOptions(mode == .ctr ? kCCModeOptionCTR_BE : 0),
            &cryptor,
        )
        guard created == kCCSuccess, let cryptor else {
            throw .malformed
        }
        defer { CCCryptorRelease(cryptor) }
        let capacity = data.count
        var output = [UInt8](repeating: 0, count: capacity)
        var moved = 0
        let status = CCCryptorUpdate(cryptor, data, data.count, &output, capacity, &moved)
        guard status == kCCSuccess, moved == capacity else {
            throw .malformed
        }
        return output
    }
}
