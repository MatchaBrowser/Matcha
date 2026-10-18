import AppKit
import SwiftUI

/// Icône d'un dossier d'épinglés ou d'un Space (`SidebarIcon`) : son emoji, qui garde ses couleurs ; son symbole SF,
/// teinté de `tint` ou du style en cours ; sinon `defaultSymbol` (aussi pour un symbole que ce macOS ne connaît pas,
/// reçu d'un Mac plus récent).
struct SidebarIconView: View {
    let icon: SidebarIcon
    let defaultSymbol: String
    /// Couleur du symbole ; nil : le style de premier plan en cours.
    var tint: Color?
    var size = 13.0
    /// Taille d'un emoji ; nil : `size`.
    var emojiSize: Double?
    var weight = Font.Weight.regular

    var body: some View {
        switch icon.displayed(defaultSymbol: defaultSymbol, symbolExists: Self.symbolExists) {
        case let .emoji(emoji):
            Text(verbatim: emoji)
                .font(.system(size: emojiSize ?? size))
        case let .symbol(name):
            symbol(name)
        case .default:
            symbol(defaultSymbol)
        }
    }

    @ViewBuilder private func symbol(_ name: String) -> some View {
        let image = Image(systemName: name)
            .font(.system(size: size, weight: weight))
        if let tint {
            image.foregroundStyle(tint)
        } else {
            image
        }
    }

    /// L'icône en un seul `Text` (le symbole y est une image) : passer d'un symbole à un emoji ne change que le texte,
    /// pas la structure de la vue. Pour le bouton d'un Space : sa bulle ouverte (l'éditeur) est rattachée à son élément
    /// d'accessibilité, que SwiftUI recrée sans elle quand la structure de son contenu change ; VoiceOver la perdrait
    /// dès qu'un emoji remplace le symbole.
    static func text(
        _ icon: SidebarIcon,
        defaultSymbol: String,
        tint: Color? = nil,
        size: Double = 13,
        emojiSize: Double? = nil,
        weight: Font.Weight = .regular,
    ) -> Text {
        switch icon.displayed(defaultSymbol: defaultSymbol, symbolExists: symbolExists) {
        case let .emoji(emoji):
            return Text(verbatim: emoji).font(.system(size: emojiSize ?? size))
        case let .symbol(name):
            let symbol = Text(Image(systemName: name)).font(.system(size: size, weight: weight))
            return tint.map { symbol.foregroundStyle($0) } ?? symbol
        case .default:
            return text(.symbol(defaultSymbol), defaultSymbol: defaultSymbol, tint: tint, size: size, weight: weight)
        }
    }

    /// Vrai si ce macOS connaît le symbole SF `name`.
    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
