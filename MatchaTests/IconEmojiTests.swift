import Foundation
@testable import Matcha
import Testing

/// Emoji d'icône d'un dossier ou d'un Space : un seul caractère qui s'affiche en emoji.
struct IconEmojiTests {
    @Test(arguments: ["😀", "🌿", "🇫🇷", "👩🏽‍💻", "👨‍👩‍👧", "❤️", "1️⃣", "#️⃣", "🏴󠁧󠁢󠁳󠁣󠁴󠁿", "👍🏽"])
    func `a single emoji is accepted`(emoji: String) {
        #expect(IconEmoji.validated(emoji) == emoji)
        #expect(IconEmoji.validated(" \(emoji)\n") == emoji)
        #expect(IconEmoji.latest(in: emoji) == emoji)
    }

    @Test(arguments: ["", " ", "a", "1", "#", "©", "❤", "→", "😀😀", "😀a", "ab", "é"])
    func `anything else is refused`(text: String) {
        #expect(IconEmoji.validated(text) == nil)
    }

    @Test func `the field keeps the latest emoji`() {
        #expect(IconEmoji.latest(in: "🌿🔥") == "🔥")
        #expect(IconEmoji.latest(in: "🌿 ") == "🌿")
        #expect(IconEmoji.latest(in: "🌿a") == nil)
        #expect(IconEmoji.latest(in: "") == nil)
    }
}
