import SwiftUI

/// Invisible handle on the left edge of the notes panel: dragging it changes the panel's width, shared by the windows
/// and written once at the end of a drag, like the sidebar's (`SidebarResizeHandle`).
struct NotesPanelResizeHandle: View {
    static let thickness = 8.0

    @Binding var width: Double
    @Binding var liveWidth: Double?

    @State private var drag = ResizeDrag<Double>()
    @GestureState private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: Self.thickness)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .leading))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($isDragging) { _, dragging, _ in
                        dragging = true
                    }
                    .onChanged { value in
                        // Dragging to the left widens the panel.
                        let start = drag.begin(at: NotesPanelMetrics.clampedWidth(width))
                        liveWidth = NotesPanelMetrics.clampedWidth(start - value.translation.width)
                    },
            )
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    if let liveWidth {
                        width = liveWidth
                    }
                    liveWidth = nil
                    drag.end()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Notes panel width", comment: "VoiceOver label of the notes panel's width handle"))
            .accessibilityValue(Text(
                "\(Int(NotesPanelMetrics.clampedWidth(liveWidth ?? width).rounded())) points",
                comment: "VoiceOver value of the sidebar width handle; %lld is the width in points",
            ))
            .accessibilityAdjustableAction { direction in
                let shown = NotesPanelMetrics.clampedWidth(width)
                switch direction {
                case .increment: width = NotesPanelMetrics.clampedWidth(shown + 20)
                case .decrement: width = NotesPanelMetrics.clampedWidth(shown - 20)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("notesPanelResizeHandle")
    }
}
