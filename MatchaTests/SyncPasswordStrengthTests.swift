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

    @Test func `long and varied passwords are strong`() {
        #expect(SyncPasswordStrength("Café crème, 2026 !") >= .good)
        #expect(SyncPasswordStrength("correct horse battery staple") >= .good)
        #expect(SyncPasswordStrength("vT7#qL9!mZ2@xR4$pK8^") == .strong)
        #expect(SyncPasswordStrength("un mot de passe assez long").isAcceptable)
    }
}
