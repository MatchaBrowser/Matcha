import Foundation

/// The EFF's large wordlist for passphrases (`VAULT.md` § 9.7): 7 776 distinct words, one per line after its five dice
/// (`11111<TAB>abacus`), so that each word drawn is worth log2(7 776) ≈ 12.9 bits. Shipped in the app's resources
/// (`Resources/Wordlists`, CC BY 3.0 US), read with a ceiling (review TR2) and checked whole: a list with a word too
/// many or too few, or a word twice, is refused rather than giving weaker passphrases. Pure type.
nonisolated struct PassphraseWordlist: Equatable, Sendable {
    enum Error: Swift.Error, Equatable {
        /// The list isn't in the bundle's resources.
        case missingFile
        /// The file is larger than `maximumSize`.
        case tooLarge
        /// The file isn't UTF-8, or a line isn't five dice, a tab and a word.
        case malformed
        /// A word is empty or holds something other than letters and hyphens.
        case invalidWord
        /// The list doesn't hold `wordCount` words.
        case wrongWordCount(Int)
        /// A word appears twice.
        case duplicateWord
    }

    static let resourceName = "eff_large_wordlist.txt"
    static let subdirectory = "Wordlists"
    /// 6⁵: one word for each roll of five dice.
    static let wordCount = 7776
    /// Ceiling of the read: the list is 108 800 bytes.
    static let maximumSize = 256 * 1024

    /// The words, in the order of the file.
    let words: [String]

    /// List checked: `wordCount` distinct words, each made of letters and hyphens.
    init(words: [String]) throws {
        guard words.allSatisfy(Self.isValid) else {
            throw Error.invalidWord
        }
        guard words.count == Self.wordCount else {
            throw Error.wrongWordCount(words.count)
        }
        guard Set(words).count == words.count else {
            throw Error.duplicateWord
        }
        self.words = words
    }

    /// List read from the file's content: lines of five dice (1 to 6), a tab and the word; empty lines are skipped.
    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw Error.malformed
        }
        var words: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0].count == 5, fields[0].allSatisfy({ ("1" ... "6").contains($0) }) else {
                throw Error.malformed
            }
            words.append(String(fields[1]))
        }
        try self.init(words: words)
    }

    /// List read from `url`, at most `maximumSize` bytes: the read stops one byte past the ceiling.
    init(contentsOf url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        let data = try handle.read(upToCount: Self.maximumSize + 1) ?? Data()
        guard data.count <= Self.maximumSize else {
            throw Error.tooLarge
        }
        try self.init(data: data)
    }

    /// The list shipped in `bundle`'s resources. Xcode copies the synchronized folder's resources flat
    /// (`Contents/Resources/eff_large_wordlist.txt`); a `Wordlists` subfolder is also searched, in case it is kept.
    static func bundled(in bundle: Bundle) throws -> PassphraseWordlist {
        guard let url = bundle.url(forResource: resourceName, withExtension: nil, subdirectory: subdirectory)
            ?? bundle.url(forResource: resourceName, withExtension: nil)
        else {
            throw Error.missingFile
        }
        return try PassphraseWordlist(contentsOf: url)
    }

    /// A word is not empty and holds only letters and hyphens (“t-shirt”), so that it can be capitalized and never
    /// looks like a separator made of spaces.
    private static func isValid(_ word: String) -> Bool {
        !word.isEmpty && word.allSatisfy { $0.isLetter || $0 == "-" }
    }
}
