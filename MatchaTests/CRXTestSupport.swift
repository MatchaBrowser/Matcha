import CryptoKit
import Foundation
@testable import Matcha
import Security

/// CRX3 files signed with keys made for the tests: what the Chrome Web Store produces, with a developer key of ours.
enum CRXBuilder {
    /// A developer's RSA key.
    struct Developer {
        let privateKey: SecKey
        /// `SubjectPublicKeyInfo`, as in a CRX3 proof.
        let publicKeyInfo: Data

        init() throws {
            let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
            var error: Unmanaged<CFError>?
            guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error), let publicKey = SecKeyCopyPublicKey(key),
                  let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
            else {
                throw error?.takeRetainedValue() ?? CocoaError(.featureUnsupported)
            }
            privateKey = key
            let algorithm = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
            publicKeyInfo = CRXBuilder.der(0x30, CRXBuilder.der(0x30, algorithm) + CRXBuilder.der(0x03, Data([0]) + pkcs1))
        }

        /// Chrome identifier of this developer.
        var identifier: String {
            CRXSignature.extensionIdentifier(Array(SHA256.hash(data: publicKeyInfo).prefix(16)))
        }

        func sign(_ message: Data) throws -> Data {
            var error: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) else {
                throw error?.takeRetainedValue() ?? CocoaError(.featureUnsupported)
            }
            return signature as Data
        }
    }

    /// CRX3 file of `archive` signed by `developer`; `claimedKey`: the key whose identifier the header claims
    /// (another developer's, to forge it), `archive` replaced after signing by `tamperedArchive`.
    static func crx(
        archive: Data,
        developer: Developer,
        claimedKey: Data? = nil,
        tamperedArchive: Data? = nil,
    ) throws -> Data {
        let claimed = claimedKey ?? developer.publicKeyInfo
        let signedHeader = field(1, Data(SHA256.hash(data: claimed).prefix(16)))
        let message = Data("CRX3 SignedData\0".utf8) + le32(signedHeader.count) + signedHeader + archive
        let proof = try field(1, claimed) + field(2, developer.sign(message))
        let header = field(2, proof) + field(10000, signedHeader)
        return Data("Cr24".utf8) + le32(3) + le32(header.count) + header + (tamperedArchive ?? archive)
    }

    /// CRX3 file signed with a P-256 key (`sha256_with_ecdsa`).
    static func ecdsaCRX(archive: Data, key: P256.Signing.PrivateKey) throws -> Data {
        let publicKey = key.publicKey.derRepresentation
        let signedHeader = field(1, Data(SHA256.hash(data: publicKey).prefix(16)))
        let message = Data("CRX3 SignedData\0".utf8) + le32(signedHeader.count) + signedHeader + archive
        let proof = try field(1, publicKey) + field(2, key.signature(for: message).derRepresentation)
        let header = field(3, proof) + field(10000, signedHeader)
        return Data("Cr24".utf8) + le32(3) + le32(header.count) + header + archive
    }

    /// CRX3 file of `archive` whose signed header claims the key `claimed`, with these proofs in this order: RSA
    /// (`sha256_with_rsa`) then P-256 (`sha256_with_ecdsa`); a proof with `corrupt` has one byte of its signature changed.
    static func crx(
        archive: Data,
        claimed: Data,
        rsa: [(key: Developer, corrupt: Bool)],
        ecdsa: [(key: P256.Signing.PrivateKey, corrupt: Bool)] = [],
    ) throws -> Data {
        let signedHeader = field(1, Data(SHA256.hash(data: claimed).prefix(16)))
        let message = Data("CRX3 SignedData\0".utf8) + le32(signedHeader.count) + signedHeader + archive
        var header = Data()
        for proof in rsa {
            let signature = try corrupted(proof.key.sign(message), proof.corrupt)
            header += field(2, field(1, proof.key.publicKeyInfo) + field(2, signature))
        }
        for proof in ecdsa {
            let signature = try corrupted(proof.key.signature(for: message).derRepresentation, proof.corrupt)
            header += field(3, field(1, proof.key.publicKey.derRepresentation) + field(2, signature))
        }
        header += field(10000, signedHeader)
        return Data("Cr24".utf8) + le32(3) + le32(header.count) + header + archive
    }

    private static func corrupted(_ signature: Data, _ corrupt: Bool) -> Data {
        guard corrupt, let last = signature.indices.last else {
            return signature
        }
        var changed = signature
        changed[last] ^= 0x01
        return changed
    }

    static func der(_ tag: UInt8, _ content: Data) -> Data {
        var length = Data()
        if content.count < 0x80 {
            length.append(UInt8(content.count))
        } else {
            var count = content.count
            var bytes: [UInt8] = []
            while count > 0 {
                bytes.insert(UInt8(count & 0xFF), at: 0)
                count >>= 8
            }
            length.append(0x80 | UInt8(bytes.count))
            length.append(contentsOf: bytes)
        }
        return Data([tag]) + length + content
    }

    /// Length-delimited protobuf field.
    static func field(_ number: Int, _ content: Data) -> Data {
        varint(UInt64(number << 3 | 2)) + varint(UInt64(content.count)) + content
    }

    private static func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes = Data()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private static func le32(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
    }
}
