import SwiftUI

/// Cell of a choice grid: light background on hover, tint and outline in the accent color if it is chosen.
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
