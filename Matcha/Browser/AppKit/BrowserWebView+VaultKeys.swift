import AppKit

/// The keys of the vault's list under a login field (`VAULT.md` § 8.1): while it shows rows, ↓ and ↑ move in it, ↩
/// fills the highlighted login and ⎋ closes it, before WebKit: the page doesn't get them. Any other key goes to the
/// page, whose script then withdraws the list.
extension BrowserWebView {
    override func keyDown(with event: NSEvent) {
        if let key = VaultSuggestionKey(event), vaultForms?.takeSuggestionKey(key) == true {
            return
        }
        super.keyDown(with: event)
    }
}

extension VaultSuggestionKey {
    /// The key of `event`, without a modifier; nil for any other.
    init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock])
        guard event.type == .keyDown, flags.isEmpty else {
            return nil
        }
        switch event.specialKey {
        case .downArrow:
            self = .next
        case .upArrow:
            self = .previous
        case .carriageReturn, .enter:
            self = .choose
        default:
            guard event.charactersIgnoringModifiers == "\u{1B}" else {
                return nil
            }
            self = .close
        }
    }
}
