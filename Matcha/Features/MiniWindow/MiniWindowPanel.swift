import AppKit

/// Fenêtre d'une mini-fenêtre : panneau flottant (au-dessus des fenêtres de Matcha tant que l'app est active,
/// voir `MiniWindowLevels`), barre de titre invisible : la barre d'outils SwiftUI la remplace, avec son propre
/// bouton de fermeture. Jamais restaurée au lancement suivant.
final class MiniWindowPanel: NSPanel {
    static let accessibilityID = "miniWindow"

    /// ⎋ (ou ⌘.) que ni la page ni la barre de commande n'ont gardé. Un `NSPanel` se ferme sinon tout seul.
    var cancelHandler: (() -> Void)?

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        isFloatingPanel = true
        // Un panneau se cache par défaut quand l'app passe en arrière-plan : la mini-fenêtre reste
        // (elle redescend alors au niveau normal).
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isRestorable = false
        tabbingMode = .disallowed
        // Par-dessus une app en plein écran ; dans Mission Control, ⌘` et le menu Fenêtre.
        collectionBehavior = [.fullScreenAuxiliary, .managed, .participatesInCycle]
        isExcludedFromWindowsMenu = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        contentMinSize = MiniWindowPlacement.minimumSize
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
        setAccessibilityIdentifier(Self.accessibilityID)
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool {
        true
    }

    /// Un panneau ne devient pas fenêtre principale par défaut : à l'activation de l'app, macOS ne fait passer
    /// devant que les fenêtres clé et principale, et la fenêtre du navigateur passerait alors par-dessus l'app
    /// d'où vient le raccourci.
    override var canBecomeMain: Bool {
        true
    }

    /// Sans cette surcharge, ⎋ fermerait le panneau (comportement de `NSPanel`) et la page avec lui.
    override func cancelOperation(_: Any?) {
        cancelHandler?()
    }
}
