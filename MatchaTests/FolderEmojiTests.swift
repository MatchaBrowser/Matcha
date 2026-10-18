import Foundation
@testable import Matcha
import Testing

/// Emoji d'icône d'un dossier : un seul caractère qui s'affiche en emoji.
struct FolderEmojiTests {
    @Test(arguments: ["😀", "🌿", "🇫🇷", "👩🏽‍💻", "👨‍👩‍👧", "❤️", "1️⃣", "#️⃣", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "👍🏽"])
    func `a single emoji is accepted`(emoji: String) {
        #expect(FolderEmoji.validated(emoji) == emoji)
        #expect(FolderEmoji.validated(" \(emoji)\n") == emoji)
        #expect(FolderEmoji.latest(in: emoji) == emoji)
    }

    @Test(arguments: ["", " ", "a", "1", "#", "©", "❤", "→", "😀😀", "😀a", "ab", "é"])
    func `anything else is refused`(text: String) {
        #expect(FolderEmoji.validated(text) == nil)
    }

    @Test func `the field keeps the latest emoji`() {
        #expect(FolderEmoji.latest(in: "🌿🔥") == "🔥")
        #expect(FolderEmoji.latest(in: "🌿 ") == "🌿")
        #expect(FolderEmoji.latest(in: "🌿a") == nil)
        #expect(FolderEmoji.latest(in: "") == nil)
    }
}
