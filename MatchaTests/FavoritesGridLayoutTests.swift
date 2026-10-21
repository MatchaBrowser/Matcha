import AppKit
@testable import Matcha
import SwiftUI
import Testing

/// Favorite tiles share the sidebar's width, whatever their number.
@MainActor
struct FavoritesGridLayoutTests {
    @Test func `the favorites stay on one row while they fit, then in even rows`() {
        // 220 points: the content of the default sidebar, room for four tiles.
        #expect((1 ... 9).map { FavoritesGridLayout.columns(count: $0, width: 220) } == [1, 2, 3, 4, 3, 3, 4, 4, 3])
        // The narrowest sidebar keeps three, the widest seven.
        #expect(FavoritesGridLayout.columns(count: 4, width: 160) == 2)
        #expect(FavoritesGridLayout.columns(count: 3, width: 160) == 3)
        #expect(FavoritesGridLayout.columns(count: 7, width: 380) == 7)
        #expect(FavoritesGridLayout.columns(count: 8, width: 380) == 4)
        // No room at all: one column, never zero.
        #expect(FavoritesGridLayout.columns(count: 3, width: 0) == 1)
        #expect(FavoritesGridLayout.columns(count: 0, width: 220) == 1)
    }

    @Test func `the tiles fill the width`() {
        let frames = Frames()
        let grid = FavoritesGridLayout {
            ForEach(0 ..< 5, id: \.self) { index in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("grid")) } action: { frames.values[index] = $0 }
            }
        }
        .coordinateSpace(.named("grid"))
        let host = NSHostingView(rootView: grid.frame(width: 220, alignment: .topLeading).fixedSize(horizontal: false, vertical: true))
        host.frame = CGRect(x: 0, y: 0, width: 220, height: 200)
        host.layoutSubtreeIfNeeded()

        // Five tiles: three, then two, each a third of the width less the gaps.
        let width = (220 - 2 * FavoritesGridLayout.spacing) / 3
        #expect(frames.values.count == 5)
        for (index, frame) in frames.values.sorted(by: { $0.key < $1.key }).map(\.value).enumerated() {
            #expect(abs(frame.width - width) < 0.5, "\(index): \(frame)")
            #expect(abs(frame.minX - Double(index % 3) * (width + FavoritesGridLayout.spacing)) < 0.5, "\(index): \(frame)")
            #expect(abs(frame.minY - Double(index / 3) * (44 + FavoritesGridLayout.spacing)) < 0.5, "\(index): \(frame)")
        }
    }

    private final class Frames {
        var values: [Int: CGRect] = [:]
    }
}
