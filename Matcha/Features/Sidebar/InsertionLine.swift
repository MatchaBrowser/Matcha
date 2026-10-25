import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Line marking where the dragged item will be inserted, centered on the top or bottom edge of a row.
struct InsertionLine: View {
    /// Also that of the line between two favorite tiles.
    static let thickness = 4.0

    var edge = VerticalEdge.top

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: Self.thickness)
            .offset(y: (edge == .top ? -1 : 1) * Self.thickness / 2)
    }
}
