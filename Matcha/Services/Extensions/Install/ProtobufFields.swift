import Foundation

/// Length-delimited fields of a protobuf message, by field number: all CRX3 needs. Nil if the message is malformed.
nonisolated struct ProtobufFields {
    private var fields: [Int: [[UInt8]]] = [:]

    init?(_ bytes: [UInt8]) {
        var index = 0
        while index < bytes.count {
            guard let tag = Self.varint(bytes, &index) else {
                return nil
            }
            let field = Int(tag >> 3)
            switch tag & 7 {
            case 0:
                guard Self.varint(bytes, &index) != nil else {
                    return nil
                }
            case 1:
                index += 8
            case 2:
                // Compared to what is left: a length near `Int.max` must neither trap nor overflow (review EX1).
                guard let length = Self.varint(bytes, &index).flatMap({ Int(exactly: $0) }), length <= bytes.count - index else {
                    return nil
                }
                fields[field, default: []].append(Array(bytes[index ..< index + length]))
                index += length
            case 5:
                index += 4
            default:
                return nil
            }
            guard index <= bytes.count else {
                return nil
            }
        }
    }

    func bytes(_ field: Int) -> [[UInt8]] {
        fields[field] ?? []
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard index < bytes.count else {
                return nil
            }
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << UInt64(shift)
            if byte & 0x80 == 0 {
                return value
            }
        }
        return nil
    }
}
