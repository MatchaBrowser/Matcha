import SwiftUI

/// Poignée invisible posée sur le bord droit de la barre latérale : la tirer change sa largeur.
struct SidebarResizeHandle: View {
    static let thickness = 8.0

    @Binding var width: Double

    /// Largeur au début du glissement en cours.
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .frame(width: Self.thickness)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .trailing))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        width = SidebarMetrics.clampedWidth(start + drag.translation.width)
                    }
                    .onEnded { _ in startWidth = nil },
            )
            .accessibilityElement()
            .accessibilityLabel("Sidebar width")
            .accessibilityIdentifier("sidebarResizeHandle")
    }
}
