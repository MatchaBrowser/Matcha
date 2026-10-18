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

    private static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
