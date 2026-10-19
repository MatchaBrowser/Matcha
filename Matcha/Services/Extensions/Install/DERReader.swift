import Foundation

/// The RSA key inside a DER `SubjectPublicKeyInfo` (what Chrome stores), as Security reads it (PKCS #1).
nonisolated enum DERPublicKey {
    static func rsaKey(fromSubjectPublicKeyInfo data: Data) -> Data? {
        var reader = DERReader(bytes: [UInt8](data))
        // SEQUENCE { SEQUENCE { algorithm }, BIT STRING { unused bits, RSAPublicKey } }
        guard var info = reader.element(tag: 0x30), info.element(tag: 0x30) != nil, let bits = info.element(tag: 0x03)?.bytes,
              bits.first == 0
        else {
            return nil
        }
        return Data(bits.dropFirst())
    }
}

/// Reads DER elements one after the other.
nonisolated struct DERReader {
    private(set) var bytes: [UInt8]
    private var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Content of the next element if it has tag `tag`.
    mutating func element(tag: UInt8) -> DERReader? {
        guard index + 2 <= bytes.count, bytes[index] == tag else {
            return nil
        }
        var position = index + 1
        var length = Int(bytes[position])
        position += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count > 0, count <= 4, position + count <= bytes.count else {
                return nil
            }
            length = bytes[position ..< position + count].reduce(0) { $0 << 8 | Int($1) }
            position += count
        }
        guard position + length <= bytes.count else {
            return nil
        }
        index = position + length
        return DERReader(bytes: Array(bytes[position ..< position + length]))
    }
}
