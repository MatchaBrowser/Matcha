import Foundation

/// Little-endian integers of the extension formats (zip, CRX), read at an offset from `data.startIndex` (a slice
/// included) or written (review EX24). Nil past the end. Pure type.
nonisolated enum LittleEndian {
    static func uint16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else {
            return nil
        }
        let start = data.startIndex + offset
        return UInt16(data[start]) | UInt16(data[start + 1]) << 8
    }

    static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else {
            return nil
        }
        let start = data.startIndex + offset
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(data[start + $1]) << (8 * $1) }
    }

    static func bytes(_ value: UInt16) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    static func bytes(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
