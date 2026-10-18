import AppKit

/// Boutons des extensions affichés (tâche 6.5), pour ancrer la bulle d'une action sous le sien : une vue par bouton,
/// avec l'extension et l'onglet qu'il vise. Les vues ne sont pas retenues.
@MainActor
final class ExtensionButtonAnchors {
    private struct Entry {
        weak var view: NSView?
        let identifier: String
        let tabID: UUID?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// `view` est le bouton de l'extension `identifier` qui vise l'onglet `tabID`.
    func register(_ view: NSView, identifier: String, tabID: UUID?) {
        entries = entries.filter { $0.value.view != nil }
        entries[ObjectIdentifier(view)] = Entry(view: view, identifier: identifier, tabID: tabID)
    }

    func unregister(_ view: NSView) {
        entries[ObjectIdentifier(view)] = nil
    }

    /// Bouton de l'extension `identifier` dans `window` : celui qui vise l'onglet `tabID` s'il y en a un (une carte par
    /// panneau d'un split), sinon le premier.
    func view(for identifier: String, tabID: UUID?, in window: NSWindow) -> NSView? {
        let views = entries.values.filter { $0.identifier == identifier && $0.view?.window === window }
        let match = views.first { tabID != nil && $0.tabID == tabID } ?? views.first
        return match?.view
    }
}
