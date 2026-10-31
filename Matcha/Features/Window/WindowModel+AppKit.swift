import AppKit

/// The window model and its `NSWindow`.
extension WindowModel {
    /// Follows `window` becoming the key window, as soon as it does: before the click that made it so is handled.
    func track(_ window: NSWindow?) {
        windowTabs?.bringWindowToFront = { [weak window] in
            if window?.isMiniaturized == true {
                window?.deminiaturize(nil)
            }
            window?.makeKeyAndOrderFront(nil)
        }
        windowTabs?.closeWindow = { [weak window] in
            window?.close()
        }
        keyObserver.map(NotificationCenter.default.removeObserver)
        keyObserver = window.map { window in
            NotificationCenter.default
                .addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.windowDidBecomeKey()
                    }
                }
        }
    }
}
