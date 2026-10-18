import AppKit
import SwiftUI

/// Icône d'un dossier d'épinglés : son emoji, son symbole SF teinté de `tint`, sinon le dossier par défaut (aussi pour
/// un symbole que ce macOS ne connaît pas, reçu d'un Mac plus récent).
struct FolderIconView: View {
    let icon: FolderIcon
    /// Couleur du symbole ; nil : celle du texte du système. Un emoji garde ses couleurs.
    var tint: Color?
    var size = 13.0

    var body: some View {
        switch icon {
        case let .emoji(emoji):
            Text(verbatim: emoji)
                .font(.system(size: size))
        case let .symbol(name) where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil:
            symbol(name)
        case .default, .symbol:
            symbol("folder")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size))
            .foregroundStyle(tint ?? .primary)
    }
}
