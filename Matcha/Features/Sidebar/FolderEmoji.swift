import Foundation

/// Emoji d'icône d'un dossier : un seul caractère (graphème), qui s'affiche en emoji.
nonisolated enum FolderEmoji {
    /// `text` sans les espaces autour, s'il est exactement un emoji ; sinon nil (vide, plusieurs caractères, lettre…).
    static func validated(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first, isEmoji(character) else {
            return nil
        }
        return trimmed
    }

    /// Dernier caractère de `text` s'il est un emoji : le champ garde l'emoji tapé ou choisi en dernier (le
    /// visualiseur de caractères l'ajoute après l'ancien) ; nil sinon.
    static func latest(in text: String) -> String? {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last, isEmoji(last) else {
            return nil
        }
        return String(last)
    }

    /// Vrai si le caractère s'affiche en emoji : l'un de ses scalaires a la présentation emoji par défaut (😀, 🇫🇷,
    /// 👩🏽‍💻), ou il commence par un emoji suivi du sélecteur de variante 16, U+FE0F (❤️, 1️⃣). Un chiffre, « © »
    /// ou « ❤ » seuls n'en sont pas.
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
