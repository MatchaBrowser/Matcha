import AppKit
import SwiftUI

/// Signale la fenêtre de navigation aux mini-fenêtres (« Ouvrir dans le Space », Space visé, profil des nouvelles
/// mini-fenêtres) : à son apparition, quand sa `NSWindow` change, et à sa disparition. Jamais une fenêtre privée.
struct MainWindowLinkModifier: ViewModifier {
    let session: BrowserSession
    let model: WindowModel
    let window: NSWindow?
    let dismissCommandBar: @MainActor () -> Void

    /// Absent des fenêtres privées.
    @Environment(MiniWindowManager.self) private var miniWindows: MiniWindowManager?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: link)
            .onChange(of: window) { link() }
            .onDisappear {
                if !session.isPrivate {
                    miniWindows?.unlinkMainWindow(model)
                }
            }
    }

    private func link() {
        guard !session.isPrivate, let miniWindows else {
            return
        }
        miniWindows.linkMainWindow(BrowserWindowLink(windowModel: model, window: window, dismissCommandBar: dismissCommandBar))
    }
}

extension View {
    /// Voir `MainWindowLinkModifier`.
    func linkedToMiniWindows(
        session: BrowserSession,
        model: WindowModel,
        window: NSWindow?,
        dismissCommandBar: @escaping @MainActor () -> Void,
    ) -> some View {
        modifier(MainWindowLinkModifier(session: session, model: model, window: window, dismissCommandBar: dismissCommandBar))
    }
}
