import SwiftUI

/// Grid of the favorites: the tiles share the width, all on one row while they keep `minimumTileWidth`, then in rows
/// as even as possible (five favorites: three, then two), like Arc.
struct FavoritesGridLayout: Layout {
    static let spacing = 6.0
    static let minimumTileWidth = 44.0

    /// Number of columns for `count` tiles in `width` points.
    nonisolated static func columns(count: Int, width: Double) -> Int {
        guard count > 0 else {
            return 1
        }
        let fitting = max(1, Int((width + spacing) / (minimumTileWidth + spacing)))
        let rows = (count + fitting - 1) / fitting
        return (count + rows - 1) / rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        guard !subviews.isEmpty else {
            return .zero
        }
        let width = proposal.width ?? Double(min(subviews.count, 4)) * (Self.minimumTileWidth + Self.spacing) - Self.spacing
        let grid = Grid(count: subviews.count, width: width)
        let height = grid.rowHeights(of: subviews).reduce(0, +) + Double(grid.rows - 1) * Self.spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let grid = Grid(count: subviews.count, width: bounds.width)
        var top = bounds.minY
        for (row, height) in grid.rowHeights(of: subviews).enumerated() {
            for column in 0 ..< grid.columns {
                let index = row * grid.columns + column
                guard index < subviews.count else {
                    break
                }
                let leading = bounds.minX + Double(column) * (grid.tileWidth + Self.spacing)
                subviews[index].place(at: CGPoint(x: leading, y: top), proposal: ProposedViewSize(width: grid.tileWidth, height: height))
            }
            top += height + Self.spacing
        }
    }

    private struct Grid {
        let columns: Int
        let rows: Int
        let tileWidth: Double

        init(count: Int, width: Double) {
            columns = FavoritesGridLayout.columns(count: count, width: width)
            rows = (count + columns - 1) / columns
            tileWidth = max(0, (width - Double(columns - 1) * FavoritesGridLayout.spacing) / Double(columns))
        }

        /// Height of each row: its tallest tile at the shared width.
        func rowHeights(of subviews: LayoutSubviews) -> [Double] {
            (0 ..< rows).map { row in
                subviews[(row * columns) ..< min((row + 1) * columns, subviews.count)]
                    .map { $0.sizeThatFits(ProposedViewSize(width: tileWidth, height: nil)).height }
                    .max() ?? 0
            }
        }
    }
}
