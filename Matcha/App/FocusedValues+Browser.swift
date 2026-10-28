import SwiftUI

/// What the active window exposes to menu commands.
extension FocusedValues {
    /// Tabs of the active window.
    @Entry var tabManager: TabManager?
    /// Actions of the active window (sidebar, address pill).
    @Entry var windowActions: WindowActions?
    /// Translation sessions of the active window (task 9.3).
    @Entry var translationHost: TranslationHost?
}
