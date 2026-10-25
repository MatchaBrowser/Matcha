import Foundation

/// Strength of a master password, for the gauge of Settings > Sync (`SYNC.md` § 3.9: the server receives `authKey`,
/// and a malicious one could try passwords offline). An estimate of the guessing work, in bits: the alphabet used, the
/// length, minus repetitions and runs, and common words and years counted as one guess each (“Matcha2026!!” is weak,
/// review SY20). 12 characters at least (`SyncPassword.minimumLength`). Pure type.
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

    /// Words tried first by anyone guessing passwords, in the app's languages; a few bits each.
    static let commonWords = [
        "password", "passwort", "motdepasse", "contrasena", "contraseña", "matcha", "qwerty", "qwertz", "azerty",
        "admin", "welcome", "bienvenue", "willkommen", "benvenuto", "bienvenido", "letmein", "iloveyou", "jetaime",
        "bonjour", "hallo", "hola", "ciao", "soleil", "sonne", "amour", "amore", "liebe", "dragon", "monkey", "football",
        "baseball", "master", "shadow", "sunshine", "princess", "secret", "geheim", "segreto", "secreto", "summer",
        "winter", "autumn", "spring", "apple", "google", "facebook",
    ].sorted { $0.count > $1.count }
    /// Bits of a common word or of a year: about the size of their list.
    static let wordBits = 6.0
    static let yearBits = 7.0

    /// Bits of the password: a common word or a year (1900 to 2099) counts as one guess; each other character, log2
    /// of its alphabet, unless it is a repetition or a run (“aaaa”, “1234”, “abcd”) of the previous one.
    static func estimatedBits(of password: String) -> Double {
        let characters = Array(password)
        // Character by character: lowercasing the whole text can change its length (“İ”).
        let folded = characters.map { $0.lowercased().first ?? $0 }
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
        var index = 0
        while index < characters.count {
            if let length = guessedLength(in: folded, at: index) {
                bits += length.isYear ? yearBits : wordBits
                index += length.count
                previous = nil
                step = nil
                continue
            }
            let character = characters[index]
            index += 1
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

    /// Length of the common word or the year that starts at `index`, if one does.
    private static func guessedLength(in characters: [Character], at index: Int) -> (count: Int, isYear: Bool)? {
        let rest = characters[index...]
        if rest.count >= 4, ["19", "20"].contains(String(rest.prefix(2))), rest.prefix(4).allSatisfy(\.isNumber) {
            return (4, true)
        }
        for word in commonWords where rest.starts(with: word) {
            return (word.count, false)
        }
        return nil
    }
}
