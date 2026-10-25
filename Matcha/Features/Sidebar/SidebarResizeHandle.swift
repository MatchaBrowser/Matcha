import SwiftUI

/// Invisible handle placed on the right edge of the sidebar: dragging it changes its width. VoiceOver reads the width
/// and changes it by steps (review IU21).
struct SidebarResizeHandle: View {
    static let thickness = 8.0
    /// One step of VoiceOver's adjustment, in points.
    static let accessibilityStep = 20.0

    /// Saved width, shared by the windows: written once, at the end of a drag (review IU1).
    @Binding var width: Double
    /// Width during a drag, for this window only; nil otherwise.
    @Binding var liveWidth: Double?

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
                        liveWidth = SidebarMetrics
                            .clampedWidth(drag.begin(at: SidebarMetrics.clampedWidth(width)) + value.translation.width)
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
            .accessibilityLabel("Sidebar width")
            .accessibilityValue(Text(
                "\(Int(shownWidth.rounded())) points",
                comment: "VoiceOver value of the sidebar width handle; %lld is the width in points",
            ))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = SidebarMetrics.clampedWidth(shownWidth + Self.accessibilityStep)
                case .decrement: width = SidebarMetrics.clampedWidth(shownWidth - Self.accessibilityStep)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("sidebarResizeHandle")
    }

    private var shownWidth: Double {
        liveWidth ?? SidebarMetrics.clampedWidth(width)
    }
}
