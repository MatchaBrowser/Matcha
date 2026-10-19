import WebKit

/// What receives the window and tab events (task 6.3): the extension controller, which gives them to each loaded
/// extension; a fake version in the tests, which records them.
@MainActor
protocol ExtensionEventSink: AnyObject {
    /// False as long as no extension is loaded: nobody to notify (an extension loaded later reads the open windows
    /// through the delegate).
    var isListening: Bool { get }
    func didOpenWindow(_ newWindow: any WKWebExtensionWindow)
    func didCloseWindow(_ closedWindow: any WKWebExtensionWindow)
    func didFocusWindow(_ focusedWindow: (any WKWebExtensionWindow)?)
    func didOpenTab(_ newTab: any WKWebExtensionTab)
    func didCloseTab(_ closedTab: any WKWebExtensionTab, windowIsClosing: Bool)
    func didActivateTab(_ activatedTab: any WKWebExtensionTab, previousActiveTab previousTab: (any WKWebExtensionTab)?)
    func didSelectTabs(_ selectedTabs: [any WKWebExtensionTab])
    func didDeselectTabs(_ deselectedTabs: [any WKWebExtensionTab])
    func didMoveTab(_ movedTab: any WKWebExtensionTab, from index: Int, in oldWindow: (any WKWebExtensionWindow)?)
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for changedTab: any WKWebExtensionTab)
}

extension WKWebExtensionController: ExtensionEventSink {
    var isListening: Bool {
        !extensionContexts.isEmpty
    }
}

extension WKWebExtension.TabChangedProperties {
    /// WebKit equivalent of the changes recorded by `ExtensionEventPlanner`.
    init(_ changes: ExtensionTabChanges) {
        var properties: WKWebExtension.TabChangedProperties = []
        if changes.contains(.loading) {
            properties.insert(.loading)
        }
        if changes.contains(.pinned) {
            properties.insert(.pinned)
        }
        if changes.contains(.playingAudio) {
            properties.insert(.playingAudio)
        }
        if changes.contains(.title) {
            properties.insert(.title)
        }
        if changes.contains(.url) {
            properties.insert(.URL)
        }
        if changes.contains(.zoomFactor) {
            properties.insert(.zoomFactor)
        }
        self = properties
    }
}
