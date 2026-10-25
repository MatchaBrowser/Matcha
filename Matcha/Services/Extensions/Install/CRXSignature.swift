import CryptoKit
import Foundation
import Security

/// Publisher of a Chrome extension file (audit E1): in a CRX3 file, the developer's key signs the archive, and the
/// extension identifier Chrome shows (32 letters from a to p) is derived from that key. A signature that checks out
/// proves that two files come from the same developer: only then is a file an update that keeps the installed
/// extension's data. Format: “Cr24”, version 3, header length, header (protobuf `CrxFileHeader`), zip archive; signed
/// data: “CRX3 SignedData\0”, length of `signed_header_data`, `signed_header_data`, archive. Pure type.
nonisolated enum CRXSignature {
    /// Chrome extension identifier of the developer whose signature checks out; nil for another format, an unsigned
    /// file, or a file one of whose proofs doesn't check out (Chrome refuses it too, review EX16).
    static func verifiedPublisher(of data: Data) -> String? {
        guard data.count > 12, data.prefix(4).elementsEqual("Cr24".utf8), LittleEndian.uint32(data, at: 4) == 3,
              let headerLength = LittleEndian.uint32(data, at: 8).map(Int.init), headerLength <= data.count - 12
        else {
            return nil
        }
        let headerStart = data.startIndex + 12
        let header = [UInt8](data[headerStart ..< headerStart + headerLength])
        guard let fields = ProtobufFields(header), let signedHeader = fields.bytes(10000).first,
              let crxID = ProtobufFields(signedHeader)?.bytes(1).first, crxID.count == 16
        else {
            return nil
        }
        let digest = signedDigest(signedHeader: signedHeader, archive: data[(headerStart + headerLength)...])
        // The developer's proof is the one whose key gives the identifier written in the signed header.
        let proofs = fields.bytes(2).map { (proof: $0, isRSA: true) } + fields.bytes(3).map { (proof: $0, isRSA: false) }
        var hasDeveloperProof = false
        for (proof, isRSA) in proofs {
            guard let parts = ProtobufFields(proof), let key = parts.bytes(1).first, let signature = parts.bytes(2).first else {
                return nil
            }
            let verified = isRSA
                ? verifyRSA(signature: Data(signature), digest: digest, publicKey: Data(key))
                : verifyECDSA(signature: Data(signature), digest: digest, publicKey: Data(key))
            guard verified else {
                return nil
            }
            hasDeveloperProof = hasDeveloperProof || Array(SHA256.hash(data: Data(key)).prefix(16)) == crxID
        }
        return hasDeveloperProof ? extensionIdentifier(crxID) : nil
    }

    /// Digest of the signed data, computed piece by piece: the archive (up to 256 MiB) is never copied (review EX17).
    private static func signedDigest(signedHeader: [UInt8], archive: Data) -> SHA256.Digest {
        var hasher = SHA256()
        hasher.update(data: Data("CRX3 SignedData\0".utf8))
        hasher.update(data: LittleEndian.bytes(UInt32(signedHeader.count)))
        hasher.update(data: signedHeader)
        hasher.update(data: archive)
        return hasher.finalize()
    }

    /// Chrome's form of an identifier: each half-byte as a letter from a to p.
    static func extensionIdentifier(_ id: [UInt8]) -> String {
        String(id.flatMap { [$0 >> 4, $0 & 0x0F] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }

    private static func verifyRSA(signature: Data, digest: SHA256.Digest, publicKey: Data) -> Bool {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let pkcs1 = DERPublicKey.rsaKey(fromSubjectPublicKeyInfo: publicKey),
              let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
        else {
            return false
        }
        return SecKeyVerifySignature(key, .rsaSignatureDigestPKCS1v15SHA256, Data(digest) as CFData, signature as CFData, nil)
    }

    private static func verifyECDSA(signature: Data, digest: SHA256.Digest, publicKey: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signature)
        else {
            return false
        }
        return key.isValidSignature(signature, for: digest)
    }
}
