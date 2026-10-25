import SwiftUI

/// Square icon button of the sidebar, highlighted on hover.
struct SidebarIconButtonStyle: ButtonStyle {
    /// Side of the button, in points.
    static let size = 26.0

    func makeBody(configuration: Configuration) -> some View {
        SidebarIconButton(configuration: configuration)
    }
}

private struct SidebarIconButton: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: SidebarIconButtonStyle.size, height: SidebarIconButtonStyle.size)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered && isEnabled ? 0.1 : 0)),
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 0.85) : 0.3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}
