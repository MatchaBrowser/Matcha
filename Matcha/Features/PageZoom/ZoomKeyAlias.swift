import AppKit

/// ⌘= vaut ⌘+ (« Zoom avant »), comme dans Safari : sur un clavier où « + » se tape avec Maj (QWERTY, AZERTY), on
/// zoome sans Maj. Un menu AppKit ne reconnaît que le caractère de son raccourci (« + ») : `BrowserWebView` propose au
/// menu un ⌘+ à la place du ⌘=.
nonisolated enum ZoomKeyAlias {
    /// Vrai pour ⌘= (Maj permise, ni ⌥ ni ⌃).
    static func isZoomIn(charactersIgnoringModifiers characters: String?, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let flags = modifierFlags.intersection([.command, .option, .control])
        return characters == "=" && flags == .command
    }

    /// ⌘+ équivalent à `event`, ou nil si `event` n'est pas ⌘=.
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
