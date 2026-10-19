import SwiftUI

/// Background of a row or a tile: marked for the selected tab, light on hover.
struct SidebarRowBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var cornerRadius = 8.0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill)
            .shadow(color: .black.opacity(isSelected && colorScheme == .light ? 0.08 : 0), radius: 1, y: 1)
            .overlay {
                // “Increase contrast” (audit H3): the selected row is outlined, not only lighter.
                if isSelected, contrast == .increased {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                }
            }
    }

    private var fill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.8))
        }
        return isHovered ? AnyShapeStyle(.subtleFill) : AnyShapeStyle(Color.clear)
    }
}
