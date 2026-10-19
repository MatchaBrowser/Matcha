import AppKit
@testable import Matcha
import Testing

/// Menus of task 5.4, read in the tests' host app: “Print…” (⌘P) and the zoom commands (⌘0, ⌘+, ⌘-) exist only once,
/// and “Export as PDF…” sits right before “Print…”, without a shortcut.
@MainActor
struct PageMenuTests {
    /// Items of all the app's menus, submenus included.
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
        // The three zoom commands are next to each other, in the same menu as “Reload Page” (⌘R).
        let zoomMenu = try #require(items("+", in: menu).first?.menu)
        #expect(items("0", in: menu).first?.menu === zoomMenu)
        #expect(items("-", in: menu).first?.menu === zoomMenu)
        #expect(items("r", in: menu).first?.menu === zoomMenu)
    }
}
