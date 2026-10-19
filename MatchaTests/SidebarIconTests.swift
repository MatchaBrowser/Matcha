import AppKit
import Foundation
@testable import Matcha
import Testing

/// Icon of a folder or a Space: stored form for a Space (`SpaceRecord.symbol`), what the sidebar draws, symbol circled
/// in the grid, symbols offered to Spaces.
struct SidebarIconTests {
    /// Values from before emoji, bare symbol names, are read as they are and written back identically.
    @MainActor
    @Test func `legacy space symbols are read as symbols`() {
        for name in BrowserSession.spaceSymbols + ["building.2.fill", "music.note"] {
            #expect(SidebarIcon(spaceSymbol: name) == .symbol(name), "\(name)")
            #expect(SidebarIcon(spaceSymbol: name).spaceSymbol == name, "\(name)")
        }
    }

    @Test func `space icons with a prefix`() {
        #expect(SidebarIcon(spaceSymbol: "symbol:house.fill") == .symbol("house.fill"))
        #expect(SidebarIcon(spaceSymbol: "emoji:🌿") == .emoji("🌿"))
        #expect(SidebarIcon(spaceSymbol: "emoji: 🇫🇷 ") == .emoji("🇫🇷"))
        // A symbol is written without a prefix, as before; an emoji with one.
        #expect(SidebarIcon.symbol("house.fill").spaceSymbol == "house.fill")
        #expect(SidebarIcon.emoji("🌿").spaceSymbol == "emoji:🌿")
        #expect(SidebarIcon.default.spaceSymbol == SidebarIcon.defaultSpaceSymbol)
    }

    @Test func `space icons round trip`() {
        let icons: [SidebarIcon] = [.symbol("star.fill"), .symbol("wrench.and.screwdriver.fill"), .emoji("👩🏽‍💻"), .emoji("🇫🇷"), .emoji("❤️")]
        for icon in icons {
            #expect(SidebarIcon(spaceSymbol: icon.spaceSymbol) == icon, "\(icon)")
        }
    }

    /// A store edited by hand, a sync or a future version: a Space always keeps an icon, the circle.
    @Test(arguments: ["", " ", "Star", "star fill", "🌿", "symbol:", "symbol:Star", "emoji:", "emoji:a", "emoji:😀😀", "other:x"])
    func `unreadable space icons give the circle`(stored: String) {
        #expect(SidebarIcon(spaceSymbol: stored) == .symbol(SidebarIcon.defaultSpaceSymbol))
    }

    @Test func `drawn icon falls back to the default symbol`() {
        let known: (String) -> Bool = { $0 != "symbol.from.the.future" }
        #expect(SidebarIcon.emoji("🌿").displayed(defaultSymbol: "circle.fill", symbolExists: known) == .emoji("🌿"))
        #expect(SidebarIcon.symbol("star.fill").displayed(defaultSymbol: "circle.fill", symbolExists: known) == .symbol("star.fill"))
        #expect(
            SidebarIcon.symbol("symbol.from.the.future").displayed(defaultSymbol: "circle.fill", symbolExists: known)
                == .symbol("circle.fill"),
        )
        #expect(SidebarIcon.default.displayed(defaultSymbol: "folder", symbolExists: known) == .symbol("folder"))
        // An emoji does not depend on the system's symbols.
        #expect(SidebarIcon.emoji("🌿").displayed(defaultSymbol: "folder") { _ in false } == .emoji("🌿"))
    }

    @Test func `picker selection and emoji`() {
        #expect(SidebarIcon.default.selectedSymbol(defaultSymbol: "folder") == "folder")
        #expect(SidebarIcon.symbol("star").selectedSymbol(defaultSymbol: "folder") == "star")
        #expect(SidebarIcon.emoji("🌿").selectedSymbol(defaultSymbol: "folder") == nil)
        #expect(SidebarIcon.emoji("🌿").emoji == "🌿")
        #expect(SidebarIcon.symbol("star").emoji == nil)
        #expect(SidebarIcon.default.emoji == nil)
    }

    /// The symbols for new Spaces come first, in their order; all of them exist on this macOS.
    @MainActor
    @Test func `every space symbol exists on this macOS`() {
        let names = SymbolChoice.spaceIcons.map(\.name)
        #expect(Array(names.prefix(BrowserSession.spaceSymbols.count)) == BrowserSession.spaceSymbols)
        #expect(names.first == SidebarIcon.defaultSpaceSymbol)
        #expect(names.count >= 40)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
            #expect(SidebarIcon.isSymbolName(name), "\(name)")
            #expect(SidebarIcon(spaceSymbol: name) == .symbol(name), "\(name)")
        }
    }
}
