import AppKit

/// ⌘= counts as ⌘+ (“Zoom In”), as in Safari: on a keyboard where “+” is typed with Shift (QWERTY, AZERTY), you
/// zoom without Shift. An AppKit menu only recognizes its shortcut's character (“+”): `BrowserWebView` offers the
/// menu a ⌘+ instead of the ⌘=.
nonisolated enum ZoomKeyAlias {
    /// True for ⌘= (Shift allowed, neither ⌥ nor ⌃).
    static func isZoomIn(charactersIgnoringModifiers characters: String?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let flags = modifierFlags.intersection([.command, .option, .control])
        return characters == "=" && flags == .command
    }

    /// ⌘+ equivalent to `event`, or nil if `event` is not ⌘=.
    @MainActor
    static func zoomInEvent(for event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown,
              isZoomIn(charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifierFlags: event.modifierFlags)
        else {
            return nil
        }
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: "+",
            charactersIgnoringModifiers: "+",
            isARepeat: event.isARepeat,
            keyCode: event.keyCode,
        )
    }
}
