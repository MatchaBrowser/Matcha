import SwiftUI

/// Handle between two panes of a split: it fills the gap between the cards, without ever covering a page. Dragging
/// it adjusts the widths; a double-click equalizes them; VoiceOver adjusts it step by step.
struct SplitDivider: View {
    /// Horizontal movement since the start of the drag.
    let onDrag: (Double) -> Void
    /// End of a drag, even a cancelled one (a dialog of the page during the drag, review ON25).
    let onDragEnded: () -> Void
    /// Double-click: equal fractions.
    let onReset: () -> Void
    /// VoiceOver: +1 (Increment) or -1 (Decrement).
    let onStep: (Int) -> Void

    @State private var isHovered = false
    /// Reset by SwiftUI at the end of a drag, even a cancelled one, unlike `onEnded`.
    @GestureState private var isDragging = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Color.primary.opacity(isHovered || isDragging ? 0.35 : 0))
                    .frame(width: 3, height: 32)
            }
            .pointerStyle(.columnResize)
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($isDragging) { _, dragging, _ in
                        dragging = true
                    }
                    .onChanged { drag in onDrag(drag.translation.width) },
            )
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    onDragEnded()
                }
            }
            .onTapGesture(count: 2, perform: onReset)
            .help(Text("Drag to resize. Double-click to make panes equal.", comment: "Help tag of the handle between two split view panes"))
            .accessibilityElement()
            .accessibilityLabel(Text("Pane Divider", comment: "Accessibility label of the handle between two split view panes"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onStep(1)
                case .decrement: onStep(-1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("splitDivider")
    }
}
