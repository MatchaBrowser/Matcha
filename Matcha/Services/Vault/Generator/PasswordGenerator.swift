import Foundation

/// Random passwords for the vault (`VAULT.md` § 9.7): 8 to 100 characters from the chosen sets among lowercase
/// letters, uppercase letters, digits and symbols, with at least one character of each chosen set, optionally without
/// the characters that look alike (`0 O 1 l I |`). Every character is drawn uniformly from the union of the sets, by
/// rejection (`uniformIndex(below:)`); a password that misses a set is drawn again whole, which keeps every valid
/// password equally likely. The random source is the system's (`SystemRandomNumberGenerator`, the operating system's
/// cryptographic generator) unless a test passes its own. Pure type.
nonisolated struct PasswordGenerator: Equatable, Sendable {
    /// A set of characters a password can be drawn from.
    enum CharacterClass: CaseIterable, Hashable, Sendable {
        case lowercase
        case uppercase
        case digits
        case symbols

        /// The characters of the set, in a fixed order.
        var characters: [Character] {
            switch self {
            case .lowercase: Array("abcdefghijklmnopqrstuvwxyz")
            case .uppercase: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            case .digits: Array("0123456789")
            case .symbols: Array(PasswordGenerator.symbols)
            }
        }
    }

    enum Error: Swift.Error, Equatable {
        /// The length is outside `lengthRange`.
        case lengthOutOfRange
        /// No character set was chosen.
        case noCharacterClass
    }

    static let lengthRange = 8 ... 100
    static let defaultLength = 20
    /// The symbols set: printable ASCII punctuation, quotes, backslash and backtick left out.
    static let symbols = "!#$%&()*+,-./:;<=>?@[]^_{|}~"
    /// Characters that look alike in many fonts, left out on request.
    static let ambiguousCharacters: Set<Character> = ["0", "O", "1", "l", "I", "|"]
    /// Whole draws tried before `fallback`. The worst case (8 characters, the 4 sets, no ambiguous characters) succeeds
    /// more than 2 times in 5, so the fallback is never reached in practice: it only keeps the result valid.
    static let maximumAttempts = 1000

    let length: Int
    let characterClasses: Set<CharacterClass>
    let avoidsAmbiguousCharacters: Bool

    /// Options checked: `length` within `lengthRange`, at least one set.
    init(
        length: Int = defaultLength,
        characterClasses: Set<CharacterClass> = Set(CharacterClass.allCases),
        avoidsAmbiguousCharacters: Bool = false,
    ) throws {
        guard Self.lengthRange.contains(length) else {
            throw Error.lengthOutOfRange
        }
        guard !characterClasses.isEmpty else {
            throw Error.noCharacterClass
        }
        self.length = length
        self.characterClasses = characterClasses
        self.avoidsAmbiguousCharacters = avoidsAmbiguousCharacters
    }

    /// The chosen sets, in the order of `CharacterClass.allCases`, each without the ambiguous characters if asked.
    var groups: [[Character]] {
        CharacterClass.allCases.filter(characterClasses.contains).map { characterClass in
            characterClass.characters.filter { !avoidsAmbiguousCharacters || !Self.ambiguousCharacters.contains($0) }
        }
    }

    /// Every character a password can hold: the union of `groups`.
    var alphabet: [Character] {
        groups.flatMap(\.self)
    }

    /// Strength in bits, `length × log2(alphabet size)`. An upper bound: requiring every chosen set removes a few
    /// passwords from the count (with 20 characters from the 4 sets, less than 0.2 bit).
    var entropyBits: Double {
        Double(length) * log2(Double(alphabet.count))
    }

    /// A password drawn from the system's cryptographic generator.
    func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    /// A password drawn from `generator`: uniform over the passwords of `length` characters of `alphabet` that hold
    /// every chosen set.
    func generate(using generator: inout some RandomNumberGenerator) -> String {
        let groups = groups
        let alphabet = groups.flatMap(\.self)
        let sets = groups.map(Set.init)
        for _ in 0 ..< Self.maximumAttempts {
            let password = (0 ..< length).map { _ in alphabet[generator.uniformIndex(below: alphabet.count)] }
            if sets.allSatisfy({ !$0.isDisjoint(with: password) }) {
                return String(password)
            }
        }
        return fallback(groups: groups, alphabet: alphabet, using: &generator)
    }

    /// One character of each set, the rest from the whole alphabet, then shuffled (Fisher–Yates): always valid, since
    /// `length` is at least the number of sets, but not exactly uniform, hence only after `maximumAttempts`.
    private func fallback(groups: [[Character]], alphabet: [Character], using generator: inout some RandomNumberGenerator) -> String {
        var password = groups.map { $0[generator.uniformIndex(below: $0.count)] }
        while password.count < length {
            password.append(alphabet[generator.uniformIndex(below: alphabet.count)])
        }
        for index in stride(from: password.count - 1, to: 0, by: -1) {
            password.swapAt(index, generator.uniformIndex(below: index + 1))
        }
        return String(password)
    }
}
