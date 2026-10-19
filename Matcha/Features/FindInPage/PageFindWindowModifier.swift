import AppKit
import SwiftUI

/// Gives a browser window's front page to Edit > Find (`PageFindResponder`, audit H1): when it appears, when its
/// `NSWindow` changes, and when it disappears.
struct PageFindWindowModifier: ViewModifier {
    let model: WindowModel
    let window: NSWindow?
    let closeCommandBar: () -> Void
    @Environment(\.pageFind) private var pageFind

    func body(content: Content) -> some View {
        content
            .onAppear(perform: register)
            .onChange(of: window) { old, _ in
                pageFind?.unregister(old)
                register()
            }
            .onDisappear { pageFind?.unregister(window) }
    }

    private func register() {
        pageFind?.register(PageFindResponder.Window(
            window: window,
            page: { [weak model] in model.flatMap { FrontPage.page(miniWindowTab: nil, tabManager: $0.space.tabManager) } },
            closeCommandBar: closeCommandBar,
        ))
    }
}

extension View {
    /// See `PageFindWindowModifier`.
    func findsInPages(model: WindowModel, window: NSWindow?, closeCommandBar: @escaping () -> Void) -> some View {
        modifier(PageFindWindowModifier(model: model, window: window, closeCommandBar: closeCommandBar))
    }
}
