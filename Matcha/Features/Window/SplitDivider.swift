import SwiftUI

/// Poignée entre deux panneaux d'un split : elle occupe l'intervalle entre les cartes, sans jamais couvrir
/// une page. La tirer règle les largeurs ; un double-clic les égalise ; VoiceOver la règle par pas.
struct SplitDivider: View {
    /// Déplacement horizontal depuis le début du glissement.
    let onDrag: (Double) -> Void
    let onDragEnded: () -> Void
    /// Double-clic : parts égales.
    let onReset: () -> Void
    /// VoiceOver : +1 (Augmenter) ou -1 (Diminuer).
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
