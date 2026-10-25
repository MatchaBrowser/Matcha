import AppKit
import KeyboardShortcuts
import Observation

/// Records a menu shortcut in Settings > Shortcuts, one command at a time: the next key press is the new shortcut
/// (⎋ cancels, ⌫ leaves the command without a shortcut). The key press is taken before the menus see it, and the
/// mini window's global shortcut is paused meanwhile. A shortcut that can't be used is refused with the reason.
@MainActor
@Observable
final class ShortcutRecorder {
    /// Command being recorded.
    private(set) var command: MenuShortcut?
    /// Last refusal, shown under its command until the next recording.
    private(set) var refusal: (command: MenuShortcut, problem: ShortcutProblem)?

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var store: MenuShortcutStore?

    /// Starts recording `command`, or stops if it is the one being recorded.
    func toggle(_ command: MenuShortcut, in store: MenuShortcutStore) {
        let wasRecording = self.command == command
        stop()
        refusal = nil
        guard !wasRecording else {
            return
        }
        self.command = command
        self.store = store
        KeyboardShortcuts.isEnabled = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        // The settings window goes to the background: nothing is recorded.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: NSApp.keyWindow,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        monitor = nil
        resignObserver = nil
        if command != nil {
            KeyboardShortcuts.isEnabled = true
        }
        command = nil
        store = nil
    }

    /// What a key press does while recording.
    enum Press: Equatable {
        /// ⎋ alone: recording stops, nothing changes.
        case cancel
        /// ⌫ or ⌦ alone: the command is left without a shortcut.
        case clear
        case shortcut(ShortcutKey)
        /// No shortcut can use this key: recording goes on.
        case unusable
    }

    static func press(_ event: NSEvent) -> Press {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags.isEmpty, event.keyCode == 53 {
            return .cancel
        }
        if flags.isEmpty, event.specialKey == .delete || event.specialKey == .deleteForward || event.specialKey == .backspace {
            return .clear
        }
        return ShortcutKey(event: event).map(Press.shortcut) ?? .unusable
    }

    /// True if the key press was used.
    private func handle(_ event: NSEvent) -> Bool {
        guard let command, let store else {
            return false
        }
        switch Self.press(event) {
        case .cancel:
            break
        case .clear:
            store.set(nil, for: command)
        case .unusable:
            NSSound.beep()
            return true
        case let .shortcut(key):
            let isTakenBySystem = KeyboardShortcuts.Shortcut(event: event)?.isTakenBySystem ?? false
            if let problem = store.problem(with: key, for: command, isTakenBySystem: isTakenBySystem) {
                refusal = (command, problem)
                NSSound.beep()
            } else {
                store.set(key, for: command)
            }
        }
        stop()
        return true
    }
}
