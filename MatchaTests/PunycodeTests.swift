import Foundation
@testable import Matcha
import Testing

/// Punycode (RFC 3492) and the hosts it encodes for the public suffix list (`VAULT.md` § 8.2).
struct PunycodeTests {
    private static func text(_ scalars: [UInt32]) -> String {
        String(String.UnicodeScalarView(scalars.compactMap(Unicode.Scalar.init)))
    }

    /// RFC 3492 § 7.1. The RFC's case annotation is left out of (I): its encoder writes digits in lowercase.
    @Test(arguments: [
        // (A) Arabic (Egyptian).
        ([
            0x0644, 0x064A, 0x0647, 0x0645, 0x0627, 0x0628, 0x062A, 0x0643, 0x0644, 0x0645, 0x0648, 0x0634, 0x0639,
            0x0631, 0x0628, 0x064A, 0x061F,
        ], "egbpdaj6bu4bxfgehfvwxn"),
        // (B) Chinese (simplified).
        ([0x4ED6, 0x4EEC, 0x4E3A, 0x4EC0, 0x4E48, 0x4E0D, 0x8BF4, 0x4E2D, 0x6587], "ihqwcrb4cv8a8dqg056pqjye"),
        // (D) Czech: basic code points keep their case.
        ([
            0x0050, 0x0072, 0x006F, 0x010D, 0x0070, 0x0072, 0x006F, 0x0073, 0x0074, 0x011B, 0x006E, 0x0065, 0x006D,
            0x006C, 0x0075, 0x0076, 0x00ED, 0x010D, 0x0065, 0x0073, 0x006B, 0x0079,
        ], "Proprostnemluvesky-uyb24dma41a"),
        // (G) Japanese (kanji and hiragana).
        ([
            0x306A, 0x305C, 0x307F, 0x3093, 0x306A, 0x65E5, 0x672C, 0x8A9E, 0x3092, 0x8A71, 0x3057, 0x3066, 0x304F,
            0x308C, 0x306A, 0x3044, 0x306E, 0x304B,
        ], "n8jok5ay5dzabd5bym9f0cm5685rrjetr6pdxa"),
        // (I) Russian (Cyrillic).
        ([
            0x043F, 0x043E, 0x0447, 0x0435, 0x043C, 0x0443, 0x0436, 0x0435, 0x043E, 0x043D, 0x0438, 0x043D, 0x0435,
            0x0433, 0x043E, 0x0432, 0x043E, 0x0440, 0x044F, 0x0442, 0x043F, 0x043E, 0x0440, 0x0443, 0x0441, 0x0441,
            0x043A, 0x0438,
        ], "b1abfaaepdrnnbgefbadotcwatmq2g4l"),
        // (L) 3<nen>B<gumi><kinpachi><sensei>.
        ([0x0033, 0x5E74, 0x0042, 0x7D44, 0x91D1, 0x516B, 0x5148, 0x751F], "3B-ww4c5e180e575a65lsy2b"),
        // (M) <amuro><namie>-with-SUPER-MONKEYS.
        ([
            0x5B89, 0x5BA4, 0x5948, 0x7F8E, 0x6075, 0x002D, 0x0077, 0x0069, 0x0074, 0x0068, 0x002D, 0x0053, 0x0055,
            0x0050, 0x0045, 0x0052, 0x002D, 0x004D, 0x004F, 0x004E, 0x004B, 0x0045, 0x0059, 0x0053,
        ], "-with-SUPER-MONKEYS-pc58ag80a8qai00g7n9n"),
        // (R) <sono><supiido><de>.
        ([0x305D, 0x306E, 0x30B9, 0x30D4, 0x30FC, 0x30C9, 0x3067], "d9juau41awczczp"),
        // (S) ASCII only: copied, then the delimiter.
        ([0x002D, 0x003E, 0x0020, 0x0024, 0x0031, 0x002E, 0x0030, 0x0030, 0x0020, 0x003C, 0x002D], "-> $1.00 <--"),
    ] as [([UInt32], String)])
    func `the RFC samples are encoded`(scalars: [UInt32], punycode: String) {
        #expect(Punycode.encode(Self.text(scalars)) == punycode)
    }

    @Test(arguments: [
        ("bücher.de", "xn--bcher-kva.de"),
        ("www.MÜNCHEN.de", "www.xn--mnchen-3ya.de"),
        // Decomposed (NFD) as some sources write it: normalized first.
        ("bu\u{0308}cher.de", "xn--bcher-kva.de"),
        // Ideographic and fullwidth full stops separate labels.
        ("食狮。中国", "xn--85x722f.xn--fiqs8s"),
        ("食狮．公司.cn", "xn--85x722f.xn--55qx5d.cn"),
        ("xn--bcher-kva.DE", "xn--bcher-kva.de"),
        ("пример.рф", "xn--e1afmkfd.xn--p1ai"),
    ])
    func `IDN hosts are converted to ASCII`(host: String, ascii: String) {
        #expect(Punycode.asciiHost(host) == ascii)
        #expect(PublicSuffixList.canonicalHost(host) == ascii)
    }

    @Test func `a label too long once encoded is refused`() {
        // 63 characters once encoded (“xn--”, 55 basic code points, “-”, then 3 for the “ü”): the most a label has.
        let longest = String(repeating: "a", count: 55) + "ü"
        #expect(Punycode.asciiHost(longest + ".de")?.count == 66)
        #expect(Punycode.asciiHost("a" + longest + ".de") == nil)
        #expect(Punycode.asciiHost(String(repeating: "ü", count: 10000)) == nil)
    }
}
