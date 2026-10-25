import Foundation
@testable import Matcha
import Testing

/// Bytes given one by one, counting how many were read.
private final class CountedBytes: AsyncSequence {
    typealias Element = UInt8
    private let bytes: [UInt8]
    private(set) var read = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    convenience init(_ text: String) {
        self.init(Array(text.utf8))
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let source: CountedBytes

        mutating func next() async -> UInt8? {
            guard source.read < source.bytes.count else {
                return nil
            }
            defer { source.read += 1 }
            return source.bytes[source.read]
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(source: self)
    }
}

/// Review TR2: data from outside read with a ceiling, without waiting for the end of a larger answer.
struct BoundedReadTests {
    @Test func `a body within its ceiling is read whole`() async throws {
        let data = try await BoundedRead.data(of: CountedBytes("hello"), expectedLength: 5, limit: 5)
        #expect(data == Data("hello".utf8))
        #expect(try await BoundedRead.data(of: CountedBytes("hello"), expectedLength: -1, limit: 10) == Data("hello".utf8))
    }

    @Test func `a larger body is refused as soon as it is known`() async {
        let announced = CountedBytes(Array(repeating: 1, count: 100))
        await #expect(throws: BoundedRead.TooLarge.self) {
            try await BoundedRead.data(of: announced, expectedLength: 100, limit: 10)
        }
        #expect(announced.read == 0)

        // Announced length unknown: the reading stops right after the ceiling, not at the end.
        let unannounced = CountedBytes(Array(repeating: 1, count: 100))
        await #expect(throws: BoundedRead.TooLarge.self) {
            try await BoundedRead.data(of: unannounced, expectedLength: -1, limit: 10)
        }
        #expect(unannounced.read == 11)
    }

    @Test func `an error message is read from its first bytes only`() async throws {
        let source = CountedBytes(Array(repeating: 1, count: 100))
        #expect(try await BoundedRead.prefix(of: source, limit: 8).count == 8)
        #expect(source.read == 8)
    }

    @Test func `lines end with LF, CR or CRLF, empty lines included`() async throws {
        var lines: [String] = []
        for try await line in BoundedLines(base: CountedBytes("event: changes\r\ndata: {}\n\r: ping\rlast"), limit: 64) {
            lines.append(line)
        }
        #expect(lines == ["event: changes", "data: {}", "", ": ping", "last"])
    }

    @Test func `a line that never ends is refused`() async {
        await #expect(throws: BoundedRead.TooLarge.self) {
            for try await _ in BoundedLines(base: CountedBytes(String(repeating: "x", count: 100)), limit: 32) {}
        }
    }
}
