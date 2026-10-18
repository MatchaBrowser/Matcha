import AppKit

/// Fenêtre d'une fenêtre de connexion (tâche 5.8) : une vraie fenêtre à barre de titre (le titre de la page),
/// redimensionnable, sans bouton de réduction (elle reste attachée à sa fenêtre d'origine), jamais restaurée ni
/// regroupée en onglets.
final class PopupWindow: NSWindow {
    static let accessibilityID = "popupWindow"
    static let style: NSWindow.StyleMask = [.titled, .closable, .resizable]

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: Self.style, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isRestorable = false
        tabbingMode = .disallowed
        // Par-dessus une fenêtre en plein écran ; le bouton vert agrandit sans passer en plein écran.
        collectionBehavior = [.fullScreenAuxiliary]
        let minimum = PopupWindowPlacement.minimumPageSize
        contentMinSize = CGSize(width: minimum.width, height: minimum.height + PopupAddressBar.height)
        setAccessibilityIdentifier(Self.accessibilityID)
        setFrame(frame, display: false)
    }

    /// ⌘W ferme la fenêtre de connexion, avant la page et le menu : l'élément « Fermer l'onglet » ne doit jamais
    /// viser l'onglet de la fenêtre de navigation qui est derrière.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isCloseShortcut(event) {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘W seul (sans Maj : ⇧⌘W reste « Fermer la fenêtre », qui la ferme aussi) ; le verrouillage des majuscules ne
    /// compte pas.
    static func isCloseShortcut(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }
}
