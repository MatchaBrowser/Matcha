import AppKit
import WebKit

extension KeyModifiers {
    /// The keys of `flags` that count for a link.
    nonisolated init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.shift) {
            insert(.shift)
        }
        if flags.contains(.control) {
            insert(.control)
        }
        if flags.contains(.option) {
            insert(.option)
        }
        if flags.contains(.command) {
            insert(.command)
        }
    }
}

/// What the navigation rules read of a click (`NavigationRequest`), in the same terms on every platform: WebKit gives
/// them in the platform's own types.
extension WKNavigationAction {
    /// Keys held during the click.
    var keyModifiers: KeyModifiers {
        KeyModifiers(modifierFlags)
    }

    /// Mouse buttons, as a mask: on the Mac, `buttonNumber` already is one (checked with WebKit).
    var mouseButtons: Int {
        buttonNumber
    }
}
