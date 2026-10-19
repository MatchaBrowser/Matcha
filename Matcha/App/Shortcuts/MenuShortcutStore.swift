import Foundation
import Observation
import SwiftUI

/// Why a shortcut can't go to a command (Settings > Shortcuts).
nonisolated enum ShortcutProblem: Equatable, Sendable {
    /// Neither ⌘ nor ⌃ (nor a function key).
    case needsCommandOrControl
    /// Another command of the list has it.
    case usedBy(MenuShortcut)
    /// A command that keeps its shortcut (`MenuShortcut.fixedKeys`).
    case usedByMatcha
    /// A shortcut of macOS (Mission Control, Spotlight…).
    case usedByMacOS
    /// The mini window's global shortcut.
    case usedByMiniWindowShortcut
}

/// Shortcuts of the menu commands (Settings > Shortcuts): the default ones, except those the user changed, saved in
/// the defaults (`menuShortcuts`: command → `ShortcutKey.storageValue`, empty text for no shortcut). The menus read
/// them here and follow every change.
@MainActor
@Observable
final class MenuShortcutStore {
    static let shared = MenuShortcutStore(defaults: .standard)
    nonisolated static let defaultsKey = "menuShortcuts"

    /// Changed commands: their shortcut, or nil for none.
    private(set) var overrides: [MenuShortcut: ShortcutKey?] = [:]
    /// The mini window's global shortcut, as a menu shortcut: “New Mini Window” doesn't show the same one (it would
    /// open two windows while the menu is open).
    private(set) var globalMiniWindowKey: ShortcutKey?
    @ObservationIgnored private let defaults: UserDefaults?

    /// `defaults`: nil keeps nothing (tests).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let saved = defaults?.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        for (name, value) in saved {
            guard let command = MenuShortcut(rawValue: name) else {
                continue
            }
            if value.isEmpty {
                overrides.updateValue(nil, forKey: command)
            } else if let key = ShortcutKey(storageValue: value) {
                overrides.updateValue(key, forKey: command)
            }
        }
    }

    func key(for command: MenuShortcut) -> ShortcutKey? {
        if let override = overrides[command] {
            return override
        }
        return command.defaultKey
    }

    func isCustomized(_ command: MenuShortcut) -> Bool {
        overrides.keys.contains(command)
    }

    var hasCustomizations: Bool {
        !overrides.isEmpty
    }

    /// Shortcut of the command's menu item.
    func keyboardShortcut(for command: MenuShortcut) -> KeyboardShortcut? {
        guard let key = key(for: command), command != .newMiniWindow || key != globalMiniWindowKey else {
            return nil
        }
        return key.keyboardShortcut
    }

    /// `key` nil: no shortcut. The default shortcut is no longer a change.
    func set(_ key: ShortcutKey?, for command: MenuShortcut) {
        if key == command.defaultKey {
            overrides.removeValue(forKey: command)
        } else {
            overrides.updateValue(key, forKey: command)
        }
        save()
    }

    func reset(_ command: MenuShortcut) {
        overrides.removeValue(forKey: command)
        save()
    }

    func resetAll() {
        overrides = [:]
        save()
    }

    func setGlobalMiniWindowKey(_ key: ShortcutKey?) {
        globalMiniWindowKey = key
    }

    /// Why `key` can't go to `command`; nil if it can. `isTakenBySystem`: macOS uses it.
    func problem(with key: ShortcutKey, for command: MenuShortcut, isTakenBySystem: Bool) -> ShortcutProblem? {
        if !key.isUsableInMenus {
            return .needsCommandOrControl
        }
        if MenuShortcut.fixedKeys.contains(key) {
            return .usedByMatcha
        }
        if let other = MenuShortcut.allCases.first(where: { $0 != command && self.key(for: $0) == key }) {
            return .usedBy(other)
        }
        if command != .newMiniWindow, key == globalMiniWindowKey {
            return .usedByMiniWindowShortcut
        }
        return isTakenBySystem ? .usedByMacOS : nil
    }

    private func save() {
        guard let defaults else {
            return
        }
        if overrides.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        var saved: [String: String] = [:]
        for (command, key) in overrides {
            saved[command.rawValue] = key?.storageValue ?? ""
        }
        defaults.set(saved, forKey: Self.defaultsKey)
    }
}
