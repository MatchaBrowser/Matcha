import SwiftUI

/// Grid of SF Symbols to choose from, at the available width: the chosen symbol is circled, each has its name as a
/// tooltip and for VoiceOver. Icon of a folder (customization panel) or of a Space (`SpaceEditor`).
struct SymbolPickerGrid: View {
    static let cellSize = 24.0

    let symbols: [SymbolChoice]
    /// Name of the chosen symbol, nil if none is.
    let selection: String?
    /// Prefix of the accessibility identifiers: “<prefix>.<symbol name>”.
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
