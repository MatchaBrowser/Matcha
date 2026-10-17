import AppKit
@testable import Matcha
import Testing

/// Menus de la tâche 5.4, relevés dans l'app hôte des tests : « Imprimer… » (⌘P) et les commandes de zoom (⌘0, ⌘+,
/// ⌘-) n'existent qu'une fois, et « Exporter en PDF… » se trouve juste avant « Imprimer… », sans raccourci.
@MainActor
struct PageMenuTests {
    /// Éléments de tous les menus de l'app, sous-menus compris.
    private func allItems(of menu: NSMenu?) -> [NSMenuItem] {
        (menu?.items ?? []).flatMap { [$0] + allItems(of: $0.submenu) }
    }

    private func items(_ key: String, in menu: NSMenu?) -> [NSMenuItem] {
        allItems(of: menu).filter {
            $0.keyEquivalent == key && $0.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command
        }
    }

    @Test func `print and zoom commands appear once`() throws {
        let menu = try #require(NSApp.mainMenu)
        for key in ["p", "0", "+", "-"] {
            #expect(items(key, in: menu).count == 1, "⌘\(key)")
        }
        let print = try #require(items("p", in: menu).first)
        let fileMenu = try #require(print.menu)
        let index = fileMenu.index(of: print)
        #expect(index > 0)
        #expect(fileMenu.items[index - 1].keyEquivalent.isEmpty)
        #expect(!fileMenu.items[index - 1].isSeparatorItem)
        // Les trois commandes de zoom sont voisines, dans le même menu que « Recharger la page » (⌘R).
        let zoomMenu = try #require(items("+", in: menu).first?.menu)
        #expect(items("0", in: menu).first?.menu === zoomMenu)
        #expect(items("-", in: menu).first?.menu === zoomMenu)
        #expect(items("r", in: menu).first?.menu === zoomMenu)
    }
}
