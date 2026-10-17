import AppKit

/// Réglages AppKit de la fenêtre que SwiftUI n'expose pas.
@MainActor
enum WindowChrome {
    /// Barre de titre transparente. `isMovableByWindowBackground` reste désactivé : il transformerait
    /// tout glissement sur une zone transparente (poignée, glisser-déposer) en déplacement de la fenêtre.
    static func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
    }

    /// Masque ou montre les boutons rouge, orange et vert.
    static func setButtonsHidden(_ hidden: Bool, in window: NSWindow?) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }
}
