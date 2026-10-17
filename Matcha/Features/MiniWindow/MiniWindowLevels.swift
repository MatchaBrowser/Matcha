import AppKit

/// Niveau des mini-fenêtres : au-dessus des fenêtres de Matcha tant que l'app est active ; quand une autre app
/// passe devant, au niveau normal, juste au-dessus de la fenêtre de Matcha la plus en avant (elles passent
/// derrière les fenêtres de l'autre app, mais pas derrière la fenêtre du navigateur). Jamais masquées.
@MainActor
enum MiniWindowLevels {
    static func raise(_ panels: [NSWindow]) {
        for panel in panels {
            panel.level = .floating
        }
    }

    /// Du premier plan vers l'arrière, chacune est posée juste au-dessus de l'ancre : leur ordre est gardé.
    static func lower(_ panels: [NSWindow]) {
        let windows = orderedFrontToBack()
        let ordered = windows.filter { window in panels.contains { $0 === window } }
        let anchor = windows.first { window in
            !panels.contains { $0 === window } && window.isVisible && window.level == .normal
        }
        for panel in ordered {
            panel.level = .normal
            if let anchor {
                panel.order(.above, relativeTo: anchor.windowNumber)
            }
        }
    }

    /// Fenêtres de l'app, du premier plan vers l'arrière (panneaux compris, contrairement à `NSApp.orderedWindows`).
    private static func orderedFrontToBack() -> [NSWindow] {
        (NSWindow.windowNumbers(options: []) ?? []).compactMap { NSApp.window(withWindowNumber: $0.intValue) }
    }
}
