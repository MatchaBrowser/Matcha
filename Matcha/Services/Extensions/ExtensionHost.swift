import WebKit

/// The app's windows and tabs as extensions see them (task 6.3), and the pages opened for them: interface
/// (`ExtensionWindows`), given to the manager by the app (audit C1). Errors thrown are `ExtensionError`s.
@MainActor
protocol ExtensionHost: AnyObject {
    /// Open windows, the focused one first, as WebKit asks for them.
    var windowsForExtensions: [any WKWebExtensionWindow] { get }
    var focusedWindowForExtensions: (any WKWebExtensionWindow)? { get }
    /// Reads the windows and tabs again, and tells the extensions what changed. `beforeLoading`: an extension is about
    /// to load (WebKit will ask it for the open windows).
    func update(beforeLoading: Bool)
    /// The extension tab of `page`, if extensions see it.
    func extensionTab(for page: BrowserTab) -> (any WKWebExtensionTab)?
    /// A new tab (`tabs.create`).
    func openTab(using configuration: WKWebExtension.TabConfiguration, for context: WKWebExtensionContext) throws -> any WKWebExtensionTab
    /// A new window (`windows.create`).
    func openWindow(using configuration: WKWebExtension.WindowConfiguration, for context: WKWebExtensionContext) throws
        -> any WKWebExtensionWindow
    /// `url` in a new tab of a browser window that `context` may use (never private without one), brought to the front;
    /// false without such a window.
    func openPage(_ url: URL, for context: WKWebExtensionContext?) -> Bool
    /// Shows the popover of `action`; false if it can't be.
    func presentPopup(of action: WKWebExtension.Action) -> Bool
}
