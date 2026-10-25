import Foundation

/// Downloads of a page's document (audit W7): how many it started, its last real click, “Allow” answered in the banner,
/// and the downloads waiting for that answer. A new document starts again from nothing.
@MainActor
final class PageDownloads {
    private(set) var started = 0
    private(set) var lastClick: Date?
    /// “Allow” answered in the banner: the rest of this document's downloads go without asking.
    private(set) var isAllowed = false
    /// Decisions waiting for the banner's answer.
    private var held: [(Bool) -> Void] = []

    var isWaiting: Bool {
        !held.isEmpty
    }

    /// New document: its downloads are counted from zero, and those still waiting are declined, whatever was called
    /// before (review CO7).
    func documentDidChange() {
        release(allowing: false)
        started = 0
        lastClick = nil
        isAllowed = false
    }

    func userDidClick(at date: Date) {
        lastClick = date
    }

    func didStart() {
        started += 1
    }

    /// `decision` gets the banner's answer.
    func hold(_ decision: @escaping (Bool) -> Void) {
        held.append(decision)
    }

    /// The banner's answer, for all the downloads waiting for it.
    func release(allowing: Bool) {
        let pending = held
        held = []
        if allowing {
            isAllowed = true
        }
        pending.forEach { $0(allowing) }
    }
}
