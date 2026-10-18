import WebKit

/// Ce qui reçoit les événements des fenêtres et des onglets (tâche 6.3) : le contrôleur des extensions, qui les donne à
/// chaque extension chargée ; une fausse version dans les tests, qui les note.
@MainActor
protocol ExtensionEventSink: AnyObject {
    /// Faux tant qu'aucune extension n'est chargée : rien à prévenir (une extension chargée ensuite lit les fenêtres
    /// ouvertes par le délégué).
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
    /// Équivalent WebKit des changements notés par `ExtensionEventPlanner`.
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
