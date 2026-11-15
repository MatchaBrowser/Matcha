import Foundation
@testable import Matcha
import Testing

/// Random passphrases (`VAULT.md` § 9.7): the EFF list shipped and checked, the number of words, the separator, the
/// capitals and the digit, and the strength in bits.
struct PassphraseGeneratorTests {
    private func wordlist() throws -> PassphraseWordlist {
        try PassphraseWordlist.bundled(in: .main)
    }

    /// Lines of the list's format for `words`, the dice counted from 11111.
    private func listData(_ words: [String]) -> Data {
        let lines = words.enumerated().map { index, word in
            var value = index
            var dice = ""
            for _ in 0 ..< 5 {
                dice = String(value % 6 + 1) + dice
                value /= 6
            }
            return dice + "\t" + word
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// `count` distinct words of letters: the indices in base 26, digits written `a` to `z`.
    private func letterWords(_ count: Int) -> [String] {
        (0 ..< count).map { index in
            var value = index
            var word = ""
            repeat {
                word.append(Character(UnicodeScalar(UInt8(97 + value % 26))))
                value /= 26
            } while value > 0
            return word
        }
    }

    // MARK: The list

    @Test func `the EFF list is shipped and complete`() throws {
        let list = try wordlist()
        #expect(list.words.count == 7776)
        #expect(Set(list.words).count == 7776)
        #expect(list.words.first == "abacus")
        #expect(list.words.last == "zoom")
        #expect(list.words.contains("t-shirt"))
    }

    @Test func `a list that isn't the EFF's format is refused`() throws {
        let words = letterWords(7776)
        let shorter = Array(words.dropLast())
        #expect(try PassphraseWordlist(data: listData(words)).words == words)
        #expect(throws: PassphraseWordlist.Error.wrongWordCount(7775)) { try PassphraseWordlist(data: listData(shorter)) }
        #expect(throws: PassphraseWordlist.Error.wrongWordCount(7777)) { try PassphraseWordlist(data: listData(words + ["extra"])) }
        #expect(throws: PassphraseWordlist.Error.duplicateWord) { try PassphraseWordlist(data: listData(shorter + ["a"])) }
        #expect(throws: PassphraseWordlist.Error.invalidWord) { try PassphraseWordlist(data: listData(shorter + ["two words"])) }
        #expect(throws: PassphraseWordlist.Error.malformed) { try PassphraseWordlist(data: Data("abacus\n".utf8)) }
        #expect(throws: PassphraseWordlist.Error.malformed) { try PassphraseWordlist(data: Data("11117\tabacus\n".utf8)) }
        #expect(throws: PassphraseWordlist.Error.malformed) { try PassphraseWordlist(data: Data([0x31, 0x09, 0xFF])) }
        #expect(throws: PassphraseWordlist.Error.missingFile) { try PassphraseWordlist.bundled(in: Bundle(for: TestPages.self)) }
    }

    @Test func `a file past the ceiling is not read`() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wordlist-\(UUID().uuidString).txt")
        try Data(count: PassphraseWordlist.maximumSize + 1).write(to: file)
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        #expect(throws: PassphraseWordlist.Error.tooLarge) { try PassphraseWordlist(contentsOf: file) }
    }

    // MARK: Passphrases

    @Test func `options out of bounds are refused`() throws {
        let list = try wordlist()
        #expect(throws: PassphraseGenerator.Error.wordCountOutOfRange) { try PassphraseGenerator(wordlist: list, wordCount: 2) }
        #expect(throws: PassphraseGenerator.Error.wordCountOutOfRange) { try PassphraseGenerator(wordlist: list, wordCount: 13) }
        #expect(throws: PassphraseGenerator.Error.separatorTooLong) { try PassphraseGenerator(wordlist: list, separator: "123456789") }
        let defaults = try PassphraseGenerator(wordlist: list)
        #expect(defaults.wordCount == 5 && defaults.separator == "-")
        #expect(!defaults.capitalizesWords && !defaults.includesDigit)
    }

    @Test(arguments: [3, 5, 12])
    func `passphrases have the words and separator asked`(wordCount: Int) throws {
        let list = try wordlist()
        let words = Set(list.words)
        for separator in ["-", " ", "."] {
            let generator = try PassphraseGenerator(wordlist: list, wordCount: wordCount, separator: separator)
            for _ in 0 ..< 20 {
                let parts = generator.generate().split(separator: separator, omittingEmptySubsequences: false).map(String.init)
                // A hyphenated word (“t-shirt”) splits in two at a hyphen separator.
                #expect(parts.count >= wordCount)
                if separator != "-" {
                    #expect(parts.count == wordCount)
                    #expect(parts.allSatisfy(words.contains))
                }
            }
        }
        var first = SeededGenerator(seed: UInt64(wordCount))
        var second = SeededGenerator(seed: UInt64(wordCount))
        let joined = try PassphraseGenerator(wordlist: list, wordCount: wordCount, separator: "").generate(using: &first)
        let spaced = try PassphraseGenerator(wordlist: list, wordCount: wordCount, separator: " ").generate(using: &second)
        #expect(joined == spaced.replacingOccurrences(of: " ", with: ""))
    }

    @Test func `words can be capitalized and given a digit`() throws {
        let list = try wordlist()
        let words = Set(list.words)
        let generator = try PassphraseGenerator(wordlist: list, separator: " ", capitalizesWords: true, includesDigit: true)
        var places = Set<Int>()
        for _ in 0 ..< 200 {
            let parts = generator.generate().split(separator: " ").map(String.init)
            #expect(parts.count == 5)
            #expect(parts.allSatisfy { $0.first?.isUppercase == true })
            #expect(parts.flatMap(\.self).count(where: \.isNumber) == 1)
            let place = try #require(parts.firstIndex { $0.last?.isNumber == true })
            places.insert(place)
            #expect(parts.enumerated().allSatisfy { index, part in
                words.contains((index == place ? String(part.dropLast()) : part).lowercased())
            })
        }
        #expect(places == Set(0 ..< 5))
    }

    @Test func `a seeded generator gives the same passphrases`() throws {
        let generator = try PassphraseGenerator(wordlist: wordlist(), includesDigit: true)
        var first = SeededGenerator(seed: 9)
        var second = SeededGenerator(seed: 9)
        let passphrases = (0 ..< 10).map { _ in generator.generate(using: &first) }
        let again = (0 ..< 10).map { _ in generator.generate(using: &second) }
        #expect(passphrases == again)
        #expect(Set(passphrases).count == 10)
    }

    @Test func `the strength counts the words and the digit`() throws {
        let list = try wordlist()
        #expect(try abs(PassphraseGenerator(wordlist: list).entropyBits - 64.624) < 0.001)
        #expect(try abs(PassphraseGenerator(wordlist: list, includesDigit: true).entropyBits - 70.268) < 0.001)
        #expect(try abs(PassphraseGenerator(wordlist: list, wordCount: 3, capitalizesWords: true).entropyBits - 3 * log2(7776)) < 0.000_001)
        #expect(try abs(PassphraseGenerator(wordlist: list, wordCount: 12).entropyBits - 155.098) < 0.001)
    }
}
