import Foundation
@testable import Matcha
import SwiftData
import SwiftUI
import Testing

struct SpaceThemeTests {
    private let red = ThemeColor(red: 1, green: 0, blue: 0)
    private let blue = ThemeColor(red: 0, green: 0, blue: 1)

    private func isClose(_ lhs: ThemeColor, _ rhs: ThemeColor) -> Bool {
        abs(lhs.red - rhs.red) < 0.0001 && abs(lhs.green - rhs.green) < 0.0001 && abs(lhs.blue - rhs.blue) < 0.0001
    }

    @Test func `light and dark variants lighten and darken the base colors`() {
        let theme = SpaceTheme(colors: [red, blue])
        #expect(isClose(theme.lightColors[0], ThemeColor(red: 1, green: 0.65, blue: 0.65)))
        #expect(isClose(theme.darkColors[1], ThemeColor(red: 0, green: 0, blue: 0.3)))
    }

    @Test func `a theme keeps two or three colors`() {
        #expect(SpaceTheme(colors: [red]).colors == [red, red])
        #expect(SpaceTheme(colors: [red, blue, red, blue]).colors.count == 3)
        #expect(SpaceTheme(colors: []).colors.count == 2)
    }

    @Test func `changing the colors makes the theme custom`() {
        var theme = SpaceTheme.ocean
        theme.setColors([red, blue])
        #expect(theme.name == nil)
        #expect(theme.colors == [red, blue])
    }

    @Test(arguments: [(0.0, 0.0, -1.0), (90.0, 1.0, 0.0), (135.0, 1.0, 1.0), (180.0, 0.0, 1.0)])
    func `angle gives the gradient direction`(angle: Double, horizontal: Double, vertical: Double) {
        let direction = SpaceTheme(colors: [red, blue], angle: angle).direction
        #expect(abs(direction.horizontal - horizontal) < 0.0001)
        #expect(abs(direction.vertical - vertical) < 0.0001)
    }

    @Test func `default angle goes from the top left corner to the bottom right one`() {
        let theme = SpaceTheme(colors: [red, blue])
        #expect(abs(theme.startPoint.x) < 0.0001 && abs(theme.startPoint.y) < 0.0001)
        #expect(abs(theme.endPoint.x - 1) < 0.0001 && abs(theme.endPoint.y - 1) < 0.0001)
    }

    @Test func `theme survives encoding`() {
        let theme = SpaceTheme(name: "Essai", colors: [red, blue, red], angle: 45)
        #expect(SpaceTheme.decoded(from: theme.encoded()) == theme)
        #expect(SpaceTheme.decoded(from: nil) == nil)
        #expect(SpaceTheme.decoded(from: Data("n'importe quoi".utf8)) == nil)
    }

    @Test func `there are six distinct presets`() {
        #expect(SpaceTheme.presets.count == 6)
        #expect(Set(SpaceTheme.presets.compactMap(\.name)).count == 6)
        #expect(SpaceTheme.default == SpaceTheme.lavender)
    }

    @MainActor
    @Test func `a space keeps its theme across launches`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let first = BrowserSession(container: container)
        #expect(first.spaces.first?.theme == .default)
        first.spaces.first?.setTheme(.forest)

        let second = BrowserSession(container: container)
        #expect(second.spaces.first?.theme == .forest)
    }
}
