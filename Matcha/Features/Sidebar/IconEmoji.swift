import Foundation

/// Emoji of a folder or Space icon (`SidebarIcon`): a single character (grapheme), displayed as an emoji.
nonisolated enum IconEmoji {
    /// `text` without surrounding whitespace, if it is exactly one emoji; otherwise nil (empty, several characters,
    /// letter…).
    static func validated(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first, isEmoji(character) else {
            return nil
        }
        return trimmed
    }

    /// Last character of `text` if it is an emoji: the field keeps the emoji typed or chosen last (the Character
    /// Viewer appends it after the old one); nil otherwise.
    static func latest(in text: String) -> String? {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last, isEmoji(last) else {
            return nil
        }
        return String(last)
    }

    /// True if the character displays as an emoji: one of its scalars has emoji presentation by default (😀, 🇫🇷,
    /// 👩🏽‍💻), or it starts with an emoji followed by variation selector 16, U+FE0F (❤️, 1️⃣). A digit, “©”
    /// or “❤” on their own are not.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        if scalars.contains(where: \.properties.isEmojiPresentation) {
            return true
        }
        guard let first = scalars.first, first.properties.isEmoji else {
            return false
        }
        return scalars.contains("\u{FE0F}")
    }
}
