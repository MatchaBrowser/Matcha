import Foundation

/// Strength of a master password, for the gauge of Settings > Sync (`SYNC.md` § 3.9: the server receives `authKey`,
/// and a malicious one could try passwords offline). An estimate of the guessing work, in bits: the alphabet used, the
/// length, minus repetitions and runs. 12 characters at least (`SyncPassword.minimumLength`). Pure type.
nonisolated enum SyncPasswordStrength: Int, Comparable, Sendable {
    case tooShort
    case weak
    case fair
    case good
    case strong

    init(_ password: String) {
        guard SyncPassword.isLongEnough(password) else {
            self = .tooShort
            return
        }
        let bits = Self.estimatedBits(of: password)
        self = switch bits {
        case ..<50: .weak
        case ..<70: .fair
        case ..<90: .good
        default: .strong
        }
    }

    static func < (lhs: SyncPasswordStrength, rhs: SyncPasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Accepted for an account: long enough and not weak.
    var isAcceptable: Bool {
        self >= .fair
    }

    /// Bits of the password: log2 of its alphabet for each character that isn't a repetition or a run (“aaaa”,
    /// “1234”, “abcd”) of the previous one.
    static func estimatedBits(of password: String) -> Double {
        let characters = Array(password)
        var alphabet = 0
        if characters.contains(where: \.isLowercase) {
            alphabet += 26
        }
        if characters.contains(where: \.isUppercase) {
            alphabet += 26
        }
        if characters.contains(where: \.isNumber) {
            alphabet += 10
        }
        if characters.contains(where: { $0.isWhitespace || $0.isPunctuation || $0.isSymbol }) {
            alphabet += 33
        }
        if characters.contains(where: { !$0.isASCII && $0.isLetter }) {
            alphabet += 40
        }
        let perCharacter = log2(Double(max(alphabet, 2)))
        var bits = 0.0
        var previous: Int?
        var step: Int?
        for character in characters {
            let value = character.unicodeScalars.first.map { Int($0.value) } ?? 0
            let delta = previous.map { value - $0 }
            if let delta, abs(delta) <= 1, delta == 0 || delta == step {
                // Repetition or run: almost nothing more to guess.
                bits += 1
            } else {
                bits += perCharacter
            }
            step = delta
            previous = value
        }
        return bits
    }
}
