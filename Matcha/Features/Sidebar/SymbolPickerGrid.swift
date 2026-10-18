import SwiftUI

/// Grille de symboles SF à choisir, à la largeur disponible : le symbole choisi est entouré, chacun a son nom en bulle
/// d'aide et pour VoiceOver. Icône d'un dossier ; réutilisable pour l'icône d'un Space.
struct SymbolPickerGrid: View {
    static let cellSize = 24.0

    let symbols: [SymbolChoice]
    /// Nom du symbole choisi, nil si aucun ne l'est.
    let selection: String?
    /// Préfixe des identifiants d'accessibilité : « <préfixe>.<nom du symbole> ».
    let identifierPrefix: String
    let choose: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cellSize, maximum: Self.cellSize + 6), spacing: 4)], spacing: 4) {
            ForEach(symbols) { symbol in
                let isSelected = symbol.name == selection
                Button {
                    choose(symbol.name)
                } label: {
                    Image(systemName: symbol.name)
                        .font(.system(size: 13))
                        .frame(width: Self.cellSize, height: Self.cellSize)
                }
                .buttonStyle(PickerCellButtonStyle(isSelected: isSelected))
                .help(Text(symbol.title))
                .accessibilityLabel(Text(symbol.title))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("\(identifierPrefix).\(symbol.name)")
            }
        }
    }
}

/// Case d'une grille de choix : fond léger au survol, teinte et contour de la couleur d'accent si elle est choisie.
struct PickerCellButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        PickerCell(configuration: configuration, isSelected: isSelected)
    }
}

private struct PickerCell: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovered ? 0.08 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.9 : 0), lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
