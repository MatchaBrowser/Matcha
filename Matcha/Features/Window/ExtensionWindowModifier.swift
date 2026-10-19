import AppKit
import SwiftUI

/// Reports the browser window (main or private) to extensions (task 6.3): when it appears, when its `NSWindow`
/// changes, and when it disappears.
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
    /// See `ExtensionWindowModifier`.
    func seenByExtensions(model: WindowModel, window: NSWindow?) -> some View {
        modifier(ExtensionWindowModifier(model: model, window: window))
    }
}
