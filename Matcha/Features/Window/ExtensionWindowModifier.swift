import AppKit
import SwiftUI

/// Reports the browser window (main or private) to extensions (task 6.3): when it appears, when its `NSWindow`
/// changes, and when it disappears.
struct ExtensionWindowModifier: ViewModifier {
    let model: WindowModel
    let window: NSWindow?
    @Environment(\.extensionWindows) private var windows

    func body(content: Content) -> some View {
        content
            .onAppear { windows?.windowDidAppear(model, window: window) }
            .onChange(of: window) { windows?.windowDidAppear(model, window: window) }
            .onDisappear { windows?.windowDidDisappear(model) }
    }
}

extension View {
    /// See `ExtensionWindowModifier`.
    func seenByExtensions(model: WindowModel, window: NSWindow?) -> some View {
        modifier(ExtensionWindowModifier(model: model, window: window))
    }
}
