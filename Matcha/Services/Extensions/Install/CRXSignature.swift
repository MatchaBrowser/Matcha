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
    /// file or a signature that doesn't check out.
    static func verifiedPublisher(of data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count > 12, bytes.starts(with: Array("Cr24".utf8)), uint32(bytes, at: 4) == 3,
              let headerLength = uint32(bytes, at: 8).map(Int.init), 12 + headerLength <= bytes.count
        else {
            return nil
        }
        let header = Array(bytes[12 ..< 12 + headerLength])
        let archive = bytes[(12 + headerLength)...]
        guard let fields = ProtobufFields(header), let signedHeader = fields.bytes(10000).first,
              let crxID = ProtobufFields(signedHeader)?.bytes(1).first, crxID.count == 16
        else {
            return nil
        }
        let message = Data("CRX3 SignedData\0".utf8) + littleEndian(UInt32(signedHeader.count)) + Data(signedHeader) + Data(archive)
        // The developer's proof is the one whose key gives the identifier written in the signed header.
        let proofs = fields.bytes(2).map { (proof: $0, isRSA: true) } + fields.bytes(3).map { (proof: $0, isRSA: false) }
        for (proof, isRSA) in proofs {
            guard let parts = ProtobufFields(proof), let key = parts.bytes(1).first, let signature = parts.bytes(2).first,
                  Array(SHA256.hash(data: Data(key)).prefix(16)) == crxID
            else {
                continue
            }
            let verified = isRSA
                ? verifyRSA(signature: Data(signature), message: message, publicKey: Data(key))
                : verifyECDSA(signature: Data(signature), message: message, publicKey: Data(key))
            return verified ? extensionIdentifier(crxID) : nil
        }
        return nil
    }

    /// Chrome's form of an identifier: each half-byte as a letter from a to p.
    static func extensionIdentifier(_ id: [UInt8]) -> String {
        String(id.flatMap { [$0 >> 4, $0 & 0x0F] }.map { Character(UnicodeScalar(UInt8(ascii: "a") + $0)) })
    }

    private static func verifyRSA(signature: Data, message: Data, publicKey: Data) -> Bool {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let pkcs1 = DERPublicKey.rsaKey(fromSubjectPublicKeyInfo: publicKey),
              let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
        else {
            return false
        }
        return SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, signature as CFData, nil)
    }

    private static func verifyECDSA(signature: Data, message: Data, publicKey: Data) -> Bool {
        guard let key = try? P256.Signing.PublicKey(derRepresentation: publicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: signature)
        else {
            return false
        }
        return key.isValidSignature(signature, for: message)
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset + 4 <= bytes.count else {
            return nil
        }
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    private static func littleEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
