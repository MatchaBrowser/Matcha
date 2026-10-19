import AppKit

/// Displayed extension buttons (task 6.5), to anchor an action's popover below its own: one view per button, with the
/// extension and the tab it targets. The views are not retained.
@MainActor
final class ExtensionButtonAnchors {
    private struct Entry {
        weak var view: NSView?
        let identifier: String
        let tabID: UUID?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    /// `view` is the button of extension `identifier` that targets tab `tabID`.
    func register(_ view: NSView, identifier: String, tabID: UUID?) {
        entries = entries.filter { $0.value.view != nil }
        entries[ObjectIdentifier(view)] = Entry(view: view, identifier: identifier, tabID: tabID)
    }

    func unregister(_ view: NSView) {
        entries[ObjectIdentifier(view)] = nil
    }

    /// Button of extension `identifier` in `window`: the one that targets tab `tabID` if there is one (one card per
    /// pane of a split), otherwise the first one.
    func view(for identifier: String, tabID: UUID?, in window: NSWindow) -> NSView? {
        let views = entries.values.filter { $0.identifier == identifier && $0.view?.window === window }
        let match = views.first { tabID != nil && $0.tabID == tabID } ?? views.first
        return match?.view
    }
}
