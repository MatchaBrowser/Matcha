import Foundation

/// History as seen by the pages of a Space (tabs and Peek) or of a mini window (without a Space): where and for
/// which profile to keep their visits. Absent for a private window.
struct HistoryScope {
    let store: HistoryStore
    let profileID: UUID?
    let spaceID: UUID?
}
