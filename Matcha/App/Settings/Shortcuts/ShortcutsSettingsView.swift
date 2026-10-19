import KeyboardShortcuts
import SwiftUI

/// Settings > Shortcuts: the shortcut of each menu command, which the user changes or removes (`MenuShortcutStore`),
/// and the mini window's global shortcut (none by default, audit H5). macOS's standard commands (Edit, Find, Window)
/// are changed in System Settings, like in any app.
struct ShortcutsSettingsView: View {
    let store: MenuShortcutStore
    let recorder: ShortcutRecorder

    var body: some View {
        Form {
            ForEach(MenuShortcut.Menu.allCases, id: \.self) { menu in
                Section(menu.title) {
                    ForEach(MenuShortcut.allCases.filter { $0.menu == menu }, id: \.self) { command in
                        LabeledContent(command.title) {
                            ShortcutRecorderField(command: command, store: store, recorder: recorder)
                        }
                    }
                }
            }
            Section {
                LabeledContent("Mini Window Shortcut") {
                    // Its own texts (clear, rejected shortcut) are translated by KeyboardShortcuts. Menu shortcuts are
                    // checked here, with “New Mini Window” left out: it does the same thing.
                    KeyboardShortcuts.Recorder(for: .openMiniWindow) { shortcut in
                        store.setGlobalMiniWindowKey(MiniWindowShortcut.menuKey(of: shortcut))
                    }
                    .shortcutValidation(validateGlobalShortcut)
                    .keyboardShortcutsConflictPolicy(.init(menuItem: .allow))
                    .accessibilityIdentifier("miniWindowShortcutRecorder")
                }
            } header: {
                Text("In All Apps", comment: "Settings > Shortcuts: section of the global shortcut")
            } footer: {
                Text("""
                Press this shortcut in any app to open a mini window, even when Matcha is in the background. \
                It uses the profile of the Space shown.
                """, comment: "Settings > General: note under the mini window shortcut")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        recorder.stop()
                        store.resetAll()
                    }
                    .disabled(!store.hasCustomizations)
                }
            } footer: {
                Text("""
                Click a shortcut, then type the new one: ⌫ removes it, ⎋ cancels. \
                Find, spelling and the other standard commands follow macOS: change them in System Settings > Keyboard.
                """, comment: "Settings > Shortcuts: note at the bottom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .onDisappear { recorder.stop() }
    }

    /// The global shortcut can't be one of the menus' (except “New Mini Window”).
    private func validateGlobalShortcut(_ shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
        guard let key = MiniWindowShortcut.menuKey(of: shortcut) else {
            return .allow
        }
        if let command = MenuShortcut.allCases.first(where: { $0 != .newMiniWindow && store.key(for: $0) == key }) {
            return .disallow(reason: ShortcutProblem.usedBy(command).message)
        }
        if MenuShortcut.fixedKeys.contains(key) {
            return .disallow(reason: ShortcutProblem.usedByMatcha.message)
        }
        return .allow
    }
}
