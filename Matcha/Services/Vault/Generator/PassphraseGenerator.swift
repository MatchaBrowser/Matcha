import Foundation

/// Random passphrases for the vault (`VAULT.md` § 9.7): 3 to 12 words (5 by default) of the EFF's large wordlist,
/// joined by a separator (`-` by default), optionally each with a capital initial, optionally with one digit appended
/// to one of the words. Words, digit and its place are drawn uniformly, by rejection (`uniformIndex(below:)`), from the
/// system's cryptographic generator unless a test passes its own. Pure type.
nonisolated struct PassphraseGenerator: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        /// The number of words is outside `wordCountRange`.
        case wordCountOutOfRange
        /// The separator is longer than `maximumSeparatorLength` characters.
        case separatorTooLong
    }

    static let wordCountRange = 3 ... 12
    static let defaultWordCount = 5
    static let defaultSeparator = "-"
    static let maximumSeparatorLength = 8

    let wordlist: PassphraseWordlist
    let wordCount: Int
    /// Put between the words; may be empty.
    let separator: String
    /// Each word starts with a capital letter (“Abacus-Zoom”).
    let capitalizesWords: Bool
    /// One word, drawn at random, ends with a digit drawn at random (“abacus-zoom7”).
    let includesDigit: Bool

    /// Options checked: `wordCount` within `wordCountRange`, `separator` of at most `maximumSeparatorLength`
    /// characters.
    init(
        wordlist: PassphraseWordlist,
        wordCount: Int = defaultWordCount,
        separator: String = defaultSeparator,
        capitalizesWords: Bool = false,
        includesDigit: Bool = false,
    ) throws {
        guard Self.wordCountRange.contains(wordCount) else {
            throw Error.wordCountOutOfRange
        }
        guard separator.count <= Self.maximumSeparatorLength else {
            throw Error.separatorTooLong
        }
        self.wordlist = wordlist
        self.wordCount = wordCount
        self.separator = separator
        self.capitalizesWords = capitalizesWords
        self.includesDigit = includesDigit
    }

    /// Strength in bits: `wordCount × log2(words in the list)`, plus `log2(10 × wordCount)` for the digit and its place
    /// (5 words: about 64.6 bits, 70.3 with the digit). Capitals add nothing, being always there. An upper bound: it
    /// counts every draw as a different passphrase, which an empty separator or the hyphen inside a few words
    /// (“drop-down”) can very rarely contradict.
    var entropyBits: Double {
        let words = Double(wordCount) * log2(Double(wordlist.words.count))
        return includesDigit ? words + log2(Double(10 * wordCount)) : words
    }

    /// A passphrase drawn from the system's cryptographic generator.
    func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// A passphrase drawn from `generator`.
    func generate(using generator: inout some RandomNumberGenerator) -> String {
        let list = wordlist.words
        var words = (0 ..< wordCount).map { _ in list[generator.uniformIndex(below: list.count)] }
        if capitalizesWords {
            words = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }
        if includesDigit {
            let place = generator.uniformIndex(below: words.count)
            words[place] += String(generator.uniformIndex(below: 10))
        }
        return words.joined(separator: separator)
    }
}
