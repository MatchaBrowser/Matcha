import Foundation
@testable import Matcha
import Testing

/// Random passwords (`VAULT.md` § 9.7): length, the chosen sets all present, ambiguous characters left out, uniform
/// draws by rejection, and the strength in bits.
struct PasswordGeneratorTests {
    /// Returns its values in turn, then the last one forever.
    private struct ScriptedGenerator: RandomNumberGenerator {
        var values: [UInt64]

        mutating func next() -> UInt64 {
            values.count > 1 ? values.removeFirst() : values[0]
        }
    }

    private typealias CharacterClass = PasswordGenerator.CharacterClass

    @Test func `options out of bounds are refused`() throws {
        #expect(throws: PasswordGenerator.Error.lengthOutOfRange) { try PasswordGenerator(length: 7) }
        #expect(throws: PasswordGenerator.Error.lengthOutOfRange) { try PasswordGenerator(length: 101) }
        #expect(throws: PasswordGenerator.Error.noCharacterClass) { try PasswordGenerator(characterClasses: []) }
        let defaults = try PasswordGenerator()
        #expect(defaults.length == 20)
        #expect(defaults.characterClasses == Set(CharacterClass.allCases))
        #expect(!defaults.avoidsAmbiguousCharacters)
        #expect(defaults.alphabet.count == 26 + 26 + 10 + 28)
        #expect(String(CharacterClass.symbols.characters) == "!#$%&()*+,-./:;<=>?@[]^_{|}~")
    }

    @Test(arguments: [8, 9, 20, 64, 100])
    func `passwords have the length asked and every chosen set`(length: Int) throws {
        let choices: [Set<CharacterClass>] = [[.lowercase], [.digits], [.uppercase, .symbols], Set(CharacterClass.allCases)]
        for characterClasses in choices {
            let generator = try PasswordGenerator(length: length, characterClasses: characterClasses)
            let alphabet = Set(generator.alphabet)
            for _ in 0 ..< 50 {
                let password = generator.generate()
                #expect(password.count == length)
                #expect(password.allSatisfy(alphabet.contains))
                for characterClass in characterClasses {
                    #expect(password.contains(where: characterClass.characters.contains), "\(characterClass) in \(password)")
                }
                for characterClass in Set(CharacterClass.allCases).subtracting(characterClasses) {
                    #expect(!password.contains(where: characterClass.characters.contains))
                }
            }
        }
    }

    @Test func `ambiguous characters can be left out`() throws {
        let generator = try PasswordGenerator(length: 100, avoidsAmbiguousCharacters: true)
        #expect(generator.alphabet.count == 25 + 24 + 8 + 27)
        #expect(Set(generator.alphabet).isDisjoint(with: PasswordGenerator.ambiguousCharacters))
        for _ in 0 ..< 100 {
            let password = generator.generate()
            #expect(!password.contains(where: PasswordGenerator.ambiguousCharacters.contains))
            #expect(password.allSatisfy(generator.alphabet.contains))
        }
        let digits = try PasswordGenerator(length: 8, characterClasses: [.digits], avoidsAmbiguousCharacters: true)
        #expect(digits.alphabet == Array("23456789"))
    }

    @Test func `a seeded generator gives the same passwords`() throws {
        let generator = try PasswordGenerator()
        var first = SeededGenerator(seed: 2026)
        var second = SeededGenerator(seed: 2026)
        var other = SeededGenerator(seed: 2027)
        let passwords = (0 ..< 10).map { _ in generator.generate(using: &first) }
        let again = (0 ..< 10).map { _ in generator.generate(using: &second) }
        let others = (0 ..< 10).map { _ in generator.generate(using: &other) }
        #expect(passwords == again)
        #expect(passwords != others)
        #expect(Set(passwords).count == 10)
    }

    @Test func `characters are drawn about evenly`() throws {
        let generator = try PasswordGenerator(length: 100)
        var random = SeededGenerator(seed: 7)
        var counts: [Character: Int] = [:]
        for _ in 0 ..< 1000 {
            for character in generator.generate(using: &random) {
                counts[character, default: 0] += 1
            }
        }
        // 100 000 characters over 90: about 1 111 each, give or take 33 (one standard deviation).
        let expected = 100_000 / generator.alphabet.count
        #expect(counts.count == generator.alphabet.count)
        for (character, count) in counts {
            #expect((expected * 8 / 10 ... expected * 12 / 10).contains(count), "\(character): \(count)")
        }
    }

    @Test func `indices are drawn by rejection, not by modulo`() {
        // Below 3, the mask keeps 2 bits: 3 is drawn again rather than folded onto 0.
        var scripted = ScriptedGenerator(values: [3, 7, 0b110])
        #expect(scripted.uniformIndex(below: 3) == 2)
        var one = ScriptedGenerator(values: [.max])
        #expect(one.uniformIndex(below: 1) == 0)
        var random = SeededGenerator(seed: 11)
        var counts = [Int](repeating: 0, count: 7)
        for _ in 0 ..< 70000 {
            counts[random.uniformIndex(below: 7)] += 1
        }
        #expect(counts.allSatisfy { (9000 ... 11000).contains($0) }, "\(counts)")
    }

    @Test func `a stuck generator still gives a valid password`() throws {
        let generator = try PasswordGenerator(length: 8)
        var stuck = ScriptedGenerator(values: [0])
        let password = generator.generate(using: &stuck)
        #expect(password.count == 8)
        for characterClass in CharacterClass.allCases {
            #expect(password.contains(where: characterClass.characters.contains), "\(characterClass) in \(password)")
        }
    }

    @Test func `the strength counts the alphabet`() throws {
        #expect(try abs(PasswordGenerator().entropyBits - 129.837) < 0.001)
        #expect(try abs(PasswordGenerator(avoidsAmbiguousCharacters: true).entropyBits - 127.846) < 0.001)
        #expect(try abs(PasswordGenerator(length: 8, characterClasses: [.digits]).entropyBits - 8 * log2(10)) < 0.000_001)
        #expect(try PasswordGenerator(length: 100).entropyBits > PasswordGenerator(length: 99).entropyBits)
    }
}
