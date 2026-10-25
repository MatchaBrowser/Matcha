import Foundation

/// Data from outside read with a ceiling (review TR2): a response body checks the length it announces first, then
/// stops as soon as the ceiling is passed, without waiting for the end of a larger answer. Shared by the page source,
/// the favicons, the search suggestions and sync. Pure type.
nonisolated enum BoundedRead {
    /// The data passed its ceiling.
    struct TooLarge: Error, Equatable {}

    /// The bytes of `bytes`, `TooLarge` beyond `limit`: as soon as `expectedLength` (-1: unknown) or the reading passes
    /// it.
    static func data<Bytes: AsyncSequence>(
        of bytes: Bytes,
        expectedLength: Int64,
        limit: Int,
    ) async throws -> Data where Bytes.Element == UInt8 {
        guard expectedLength <= Int64(limit) else {
            throw TooLarge()
        }
        var data = Data()
        data.reserveCapacity(Int(min(max(0, expectedLength), Int64(limit))))
        for try await byte in bytes {
            guard data.count < limit else {
                throw TooLarge()
            }
            data.append(byte)
        }
        return data
    }

    /// The first `limit` bytes of `bytes`, the rest left unread (the message of an error answer).
    static func prefix<Bytes: AsyncSequence>(of bytes: Bytes, limit: Int) async throws -> Data where Bytes.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                break
            }
        }
        return data
    }
}

/// Lines of a stream of bytes (LF, CR or CRLF), of at most `limit` bytes each: `BoundedRead.TooLarge` beyond, rather
/// than a line that grows without end (an event stream, `SYNC.md` § 4.6, review TR2). Empty lines are kept. Pure type.
nonisolated struct BoundedLines<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String

    let base: Base
    let limit: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        let limit: Int
        /// The previous line ended with CR: a LF right after it belongs to the same line end.
        var skipsLineFeed = false
        var isFinished = false

        mutating func next() async throws -> String? {
            guard !isFinished else {
                return nil
            }
            var line: [UInt8] = []
            while let byte = try await base.next(isolation: #isolation) {
                if skipsLineFeed {
                    skipsLineFeed = false
                    if byte == 0x0A {
                        continue
                    }
                }
                switch byte {
                case 0x0A:
                    return Self.text(line)
                case 0x0D:
                    skipsLineFeed = true
                    return Self.text(line)
                default:
                    guard line.count < limit else {
                        throw BoundedRead.TooLarge()
                    }
                    line.append(byte)
                }
            }
            isFinished = true
            return line.isEmpty ? nil : Self.text(line)
        }

        /// Invalid UTF-8 is replaced (U+FFFD), as an event stream requires, rather than losing the whole line.
        private static func text(_ line: [UInt8]) -> String {
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: line, as: UTF8.self)
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), limit: limit)
    }
}
