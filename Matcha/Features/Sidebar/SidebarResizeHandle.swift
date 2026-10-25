import SwiftUI

/// Invisible handle placed on the right edge of the sidebar: dragging it changes its width.
struct SidebarResizeHandle: View {
    static let thickness = 8.0

    @Binding var width: Double

    /// Width at the start of the current drag.
    @State private var drag = ResizeDrag<Double>()
    /// Reset by SwiftUI at the end of a drag, even a cancelled one, unlike `onEnded` (review ON25).
    @GestureState private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: Self.thickness)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .trailing))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($isDragging) { _, dragging, _ in
                        dragging = true
                    }
                    .onChanged { value in
                        width = SidebarMetrics.clampedWidth(drag.begin(at: width) + value.translation.width)
                    },
            )
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    drag.end()
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Sidebar width")
            .accessibilityIdentifier("sidebarResizeHandle")
    }
}
