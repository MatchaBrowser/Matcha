import Foundation
@testable import Matcha
import Testing

/// Base 32 of one-time code secrets (`VAULT.md` § 9.7): the RFC 4648 vectors, the leniency of what is typed, and the
/// refusal of anything else.
struct Base32Tests {
    /// RFC 4648, § 10, padding removed.
    private static let vectors = [
        ("", ""),
        ("f", "MY"),
        ("fo", "MZXQ"),
        ("foo", "MZXW6"),
        ("foob", "MZXW6YQ"),
        ("fooba", "MZXW6YTB"),
        ("foobar", "MZXW6YTBOI"),
    ]

    @Test func `encoding matches RFC 4648`() {
        for (text, encoded) in Self.vectors {
            #expect(Base32.encode(Data(text.utf8)) == encoded)
        }
    }

    @Test func `decoding matches RFC 4648, with or without padding`() throws {
        let padded = ["", "MY======", "MZXQ====", "MZXW6===", "MZXW6YQ=", "MZXW6YTB", "MZXW6YTBOI======"]
        for ((text, encoded), padded) in zip(Self.vectors, padded) {
            #expect(try Base32.decode(encoded) == Data(text.utf8))
            #expect(try Base32.decode(padded) == Data(text.utf8))
        }
    }

    @Test func `case, spaces, hyphens and padding are ignored`() throws {
        let secret = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(secret == Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(try Base32.decode("jbsw y3dp ehpk 3pxp") == secret)
        #expect(try Base32.decode("JBSW-Y3DP-EHPK-3PXP") == secret)
        #expect(try Base32.decode(" jBsWy3Dp\tEhPk3pXp\n==") == secret)
    }

    @Test func `other characters and impossible lengths are refused`() {
        for text in ["JBSWY3DP0", "JBSWY3DP1", "JBSWY3DP8", "JBSWY3DP!", "JBSWY3DPÉ", "MZXW6_YQ"] {
            #expect(throws: Base32.Error.invalidCharacter, "\(text)") { try Base32.decode(text) }
        }
        for text in ["M", "MZX", "MZXW6Y", "MZXW6YTBO"] {
            #expect(throws: Base32.Error.invalidLength, "\(text)") { try Base32.decode(text) }
        }
    }

    @Test func `every byte value survives a round trip`() throws {
        let bytes = Data((0 ... 255).map(UInt8.init))
        for count in 0 ... 40 {
            let data = bytes.prefix(count)
            #expect(try Base32.decode(Base32.encode(data)) == data)
        }
        #expect(Base32.encode(bytes).hasPrefix("AAAQEAYEAUDAOCAJBIFQYDIOB4IBCEQTCQKRMFYY"))
        #expect(try Base32.decode(Base32.encode(bytes)) == bytes)
    }
}
