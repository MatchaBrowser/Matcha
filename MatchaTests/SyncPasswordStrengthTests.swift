@testable import Matcha
import Testing

/// Strength gauge of the master password (task 7.9).
struct SyncPasswordStrengthTests {
    @Test func `short, repeated or sequential passwords are weak`() {
        #expect(SyncPasswordStrength("court") == .tooShort)
        #expect(SyncPasswordStrength("aaaaaaaaaaaa") == .weak)
        #expect(SyncPasswordStrength("abcdefghijkl") == .weak)
        #expect(SyncPasswordStrength("123456789012") == .weak)
        #expect(!SyncPasswordStrength("aaaaaaaaaaaa").isAcceptable)
    }

    /// Review SY20: a common word, a year and a typical suffix make a weak password, whatever its length.
    @Test func `common words and years count as one guess`() {
        #expect(SyncPasswordStrength("Matcha2026!!") == .weak)
        #expect(SyncPasswordStrength("Password1990?") == .weak)
        #expect(SyncPasswordStrength("Soleil2025!!") == .weak)
        #expect(SyncPasswordStrength("Kq7!vR2#mT9z") >= .fair)
    }

    @Test func `long and varied passwords are strong`() {
        #expect(SyncPasswordStrength("Café crème, 2026 !") >= .good)
        #expect(SyncPasswordStrength("correct horse battery staple") >= .good)
        #expect(SyncPasswordStrength("vT7#qL9!mZ2@xR4$pK8^") == .strong)
        #expect(SyncPasswordStrength("un mot de passe assez long").isAcceptable)
    }
}
