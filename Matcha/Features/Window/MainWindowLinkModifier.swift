import AppKit
import SwiftUI

/// Reports the browser window to mini windows (“Open in Space”, target Space, profile of new mini windows): when it
/// appears, when its `NSWindow` changes, when it comes to the front (the last active window is the main one), and when
/// it disappears. Never a private window, nor a window of its own tabs (it shows no Space) until “Move to…”.
struct MainWindowLinkModifier: ViewModifier {
    let session: BrowserSession
    let model: WindowModel
    let window: NSWindow?
    let dismissCommandBar: @MainActor () -> Void

    /// Absent from private windows.
    @Environment(MiniWindowManager.self) private var miniWindows: MiniWindowManager?
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear(perform: link)
            .onChange(of: window) { link() }
            .onChange(of: model.windowTabs == nil) { link() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                if let window, notification.object as? NSWindow === window {
                    link()
                }
            }
            .onDisappear {
                if !session.isPrivate {
                    miniWindows?.unlinkMainWindow(model)
                }
            }
    }

    private func link() {
        guard !session.isPrivate, model.windowTabs == nil, let miniWindows else {
            return
        }
        miniWindows.linkMainWindow(BrowserWindowLink(windowModel: model, window: window, dismissCommandBar: dismissCommandBar))
        // To reopen the main window once closed (links from other apps, task 8.2).
        miniWindows.openMainWindow = { [openWindow] in openWindow(id: MatchaApp.browserWindowID) }
    }
}

extension View {
    /// See `MainWindowLinkModifier`.
    func linkedToMiniWindows(
        session: BrowserSession,
        model: WindowModel,
        window: NSWindow?,
        dismissCommandBar: @escaping @MainActor () -> Void,
    ) -> some View {
        modifier(MainWindowLinkModifier(session: session, model: model, window: window, dismissCommandBar: dismissCommandBar))
    }
}
