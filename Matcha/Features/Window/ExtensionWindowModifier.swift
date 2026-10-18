import AppKit
import SwiftUI

/// Signale la fenêtre de navigation (principale ou privée) aux extensions (tâche 6.3) : à son apparition, quand sa
/// `NSWindow` change, et à sa disparition.
struct ExtensionWindowModifier: ViewModifier {
    let model: WindowModel
    let window: NSWindow?

    func body(content: Content) -> some View {
        content
            .onAppear { ExtensionManager.shared.windows.windowDidAppear(model, window: window) }
            .onChange(of: window) { ExtensionManager.shared.windows.windowDidAppear(model, window: window) }
            .onDisappear { ExtensionManager.shared.windows.windowDidDisappear(model) }
    }
}

extension View {
    /// Voir `ExtensionWindowModifier`.
    func seenByExtensions(model: WindowModel, window: NSWindow?) -> some View {
        modifier(ExtensionWindowModifier(model: model, window: window))
    }
}
