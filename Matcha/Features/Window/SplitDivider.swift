import SwiftUI

/// Handle between two panes of a split: it fills the gap between the cards, without ever covering a page. Dragging
/// it adjusts the widths; a double-click equalizes them; VoiceOver adjusts it step by step.
struct SplitDivider: View {
    /// Horizontal movement since the start of the drag.
    let onDrag: (Double) -> Void
    let onDragEnded: () -> Void
    /// Double-click: equal fractions.
    let onReset: () -> Void
    /// VoiceOver: +1 (Increment) or -1 (Decrement).
    let onStep: (Int) -> Void

    @State private var isHovered = false
    @State private var isDragging = false

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
                    .onChanged { drag in
                        isDragging = true
                        onDrag(drag.translation.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onDragEnded()
                    },
            )
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
