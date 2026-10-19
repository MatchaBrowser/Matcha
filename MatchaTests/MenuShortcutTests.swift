import AppKit
import Foundation
@testable import Matcha
import SwiftUI
import Testing

/// Menu shortcuts that the user changes (Settings > Shortcuts, audit H1).
@MainActor
struct MenuShortcutTests {
    private func store() throws -> (MenuShortcutStore, UserDefaults) {
        let name = "MenuShortcutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (MenuShortcutStore(defaults: defaults), defaults)
    }

    @Test func `shortcuts read and save as macOS writes them`() {
        let key = ShortcutKey("T", [.command, .shift])
        #expect(key.key == .character("t"))
        #expect(key.displayText == "⇧⌘T")
        #expect(key.storageValue == "$@t")
        #expect(ShortcutKey(storageValue: "$@t") == key)
        #expect(ShortcutKey(.function5, []).displayText == "F5")
        #expect(ShortcutKey(.tab, [.control, .option]).displayText == "⌃⌥⇥")
        #expect(ShortcutKey(storageValue: "^~{upArrow}") == ShortcutKey(.upArrow, [.control, .option]))
        // The key itself can be a modifier's symbol.
        #expect(ShortcutKey(storageValue: "@@") == ShortcutKey("@"))
        for broken in ["", "@{nothing}", "x@t", "@@@t", "@T", "$${tab}"] {
            #expect(ShortcutKey(storageValue: broken) == nil, "\(broken)")
        }
        #expect(ShortcutKey("s", [.command, .control]).keyboardShortcut == KeyboardShortcut("s", modifiers: [.command, .control]))
        #expect(ShortcutKey(.function1, []).keyboardShortcut.key.character.unicodeScalars.first?.value == 0xF704)
    }

    @Test func `every default shortcut is usable, free and different`() {
        let keys = MenuShortcut.allCases.compactMap(\.defaultKey)
        #expect(Set(keys).count == keys.count)
        for key in keys {
            #expect(key.isUsableInMenus, "\(key.displayText)")
            #expect(!MenuShortcut.fixedKeys.contains(key), "\(key.displayText)")
            #expect(ShortcutKey(storageValue: key.storageValue) == key)
        }
        #expect(MenuShortcut.toggleSidebar.defaultKey?.displayText == "⌃⌘S")
        #expect(MenuShortcut.saveAs.defaultKey?.displayText == "⌘S")
        #expect(MenuShortcut.openFile.defaultKey?.displayText == "⌘O")
        #expect(MenuShortcut.openInSpace.defaultKey?.displayText == "⇧⌘O")
    }

    @Test func `a changed shortcut is kept, and the default one is no change`() throws {
        let (store, defaults) = try store()
        store.set(ShortcutKey("b", [.command, .control]), for: .toggleSidebar)
        store.set(nil, for: .print)
        #expect(store.key(for: .toggleSidebar) == ShortcutKey("b", [.command, .control]))
        #expect(store.key(for: .print) == nil)
        #expect(store.keyboardShortcut(for: .print) == nil)

        let reread = MenuShortcutStore(defaults: defaults)
        #expect(reread.key(for: .toggleSidebar) == ShortcutKey("b", [.command, .control]))
        #expect(reread.key(for: .print) == nil)
        #expect(reread.isCustomized(.print))

        reread.set(MenuShortcut.toggleSidebar.defaultKey, for: .toggleSidebar)
        #expect(!reread.isCustomized(.toggleSidebar))
        reread.reset(.print)
        #expect(reread.key(for: .print) == ShortcutKey("p"))
        #expect(!reread.hasCustomizations)
        #expect(defaults.object(forKey: MenuShortcutStore.defaultsKey) == nil)
    }

    @Test func `unknown commands and damaged values are ignored`() throws {
        let (_, defaults) = try store()
        defaults.set(["gone": "@k", "print": "@@@p", "reloadPage": "^@r"], forKey: MenuShortcutStore.defaultsKey)
        let store = MenuShortcutStore(defaults: defaults)
        #expect(store.key(for: .print) == ShortcutKey("p"))
        #expect(store.key(for: .reloadPage) == ShortcutKey("r", [.command, .control]))
        store.resetAll()
        #expect(store.key(for: .reloadPage) == ShortcutKey("r"))
    }

    @Test func `a shortcut already used is refused with the reason`() throws {
        let (store, _) = try store()
        #expect(store.problem(with: ShortcutKey("k", []), for: .print, isTakenBySystem: false) == .needsCommandOrControl)
        #expect(store.problem(with: ShortcutKey("k", .option), for: .print, isTakenBySystem: false) == .needsCommandOrControl)
        #expect(store.problem(with: ShortcutKey(.function6, []), for: .print, isTakenBySystem: false) == nil)
        #expect(store.problem(with: ShortcutKey("t"), for: .print, isTakenBySystem: false) == .usedBy(.newTab))
        #expect(store.problem(with: ShortcutKey("p"), for: .print, isTakenBySystem: false) == nil)
        #expect(store.problem(with: ShortcutKey("f"), for: .print, isTakenBySystem: false) == .usedByMatcha)
        #expect(store.problem(with: ShortcutKey("3", .control), for: .print, isTakenBySystem: false) == .usedByMatcha)
        #expect(store.problem(with: ShortcutKey("k"), for: .print, isTakenBySystem: true) == .usedByMacOS)
        // A shortcut freed by another command can be taken.
        store.set(nil, for: .newTab)
        #expect(store.problem(with: ShortcutKey("t"), for: .print, isTakenBySystem: false) == nil)
    }

    @Test func `the mini window's global shortcut is not shown twice`() throws {
        let (store, _) = try store()
        #expect(store.keyboardShortcut(for: .newMiniWindow) == KeyboardShortcut("n", modifiers: [.command, .option]))
        store.setGlobalMiniWindowKey(ShortcutKey("n", [.command, .option]))
        #expect(store.keyboardShortcut(for: .newMiniWindow) == nil)
        store.setGlobalMiniWindowKey(ShortcutKey("m", [.command, .control, .option]))
        #expect(store.keyboardShortcut(for: .newMiniWindow) != nil)
        #expect(store.problem(with: ShortcutKey("m", [.command, .control, .option]), for: .print, isTakenBySystem: false)
            == .usedByMiniWindowShortcut)
        #expect(store.problem(with: ShortcutKey("m", [.command, .control, .option]), for: .newMiniWindow, isTakenBySystem: false) == nil)
    }

    @Test func `a key press becomes a shortcut`() throws {
        func press(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode,
            ))
        }
        #expect(try ShortcutKey(event: press("T", keyCode: 17, [.command, .shift])) == ShortcutKey("t", [.command, .shift]))
        #expect(try ShortcutKey(event: press("\u{1b}", keyCode: 53, .command)) == ShortcutKey(.escape))
        #expect(try ShortcutKey(event: press(" ", keyCode: 49, [.command, .control])) == ShortcutKey(.space, [.command, .control]))
        #expect(try ShortcutKey(event: press("\t", keyCode: 48, .control)) == ShortcutKey(.tab, .control))
        #expect(try ShortcutKey(event: press(String(Character(#require(Unicode.Scalar(0xF708)))), keyCode: 96, [])) == ShortcutKey(
            .function5,
            [],
        ))
    }

    @Test func `edit find reaches the app when no view takes it`() throws {
        let find = #selector(AppDelegate.performFindPanelAction(_:))
        // SwiftUI's app delegate, which forwards to Matcha's.
        let target = try #require(NSApp.target(forAction: find, to: nil, from: nil) as? NSObject)
        let delegate = try #require((target as? AppDelegate) ?? target.forwardingTarget(for: find) as? AppDelegate)
        // Given by `MatchaApp.init` (audit C2), like the handler of the links from other apps.
        #expect(delegate.pageFind != nil)
        #expect(delegate.incomingLinks.handler != nil)
    }
}
