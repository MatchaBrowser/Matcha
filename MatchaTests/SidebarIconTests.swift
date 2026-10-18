import AppKit
import Foundation
@testable import Matcha
import Testing

/// Icône d'un dossier ou d'un Space : forme enregistrée d'un Space (`SpaceRecord.symbol`), ce que la barre dessine,
/// symbole entouré dans la grille, symboles proposés aux Spaces.
struct SidebarIconTests {
    /// Les valeurs d'avant les emoji, des noms de symbole seuls, se lisent telles quelles et se réécrivent à l'identique.
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
        // Un symbole s'écrit sans préfixe, comme avant ; un emoji avec.
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

    /// Une base modifiée à la main, une synchro ou une version future : un Space garde toujours une icône, le cercle.
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
        // Un emoji ne dépend pas des symboles du système.
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

    /// Les symboles des nouveaux Spaces viennent en premier, dans leur ordre ; tous existent sur ce macOS.
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
