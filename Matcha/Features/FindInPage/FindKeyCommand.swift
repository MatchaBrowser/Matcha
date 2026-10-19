import Foundation

/// Find field commands read from the selectors that the field editor forwards (`control(_:textView:doCommandBy:)`),
/// hence after the input method: a composition (Japanese, dead keys) triggers none of them. ⇧Return has no selector
/// of its own: it is `insertNewline:` with Shift held down.
nonisolated enum FindKeyCommand: Equatable, Sendable {
    /// ⏎ (and ⌥⏎, ⌃⏎): next match.
    case next
    /// ⇧⏎: previous match.
    case previous
    /// ⎋ (and ⌥⎋): closes the bar.
    case close

    /// Nil for a selector the editor handles itself (⇥ changes field, ↑ ↓ move the cursor…).
    init?(selectorName: String, isShiftDown: Bool) {
        switch selectorName {
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertLineBreak:":
            self = isShiftDown ? .previous : .next
        case "cancelOperation:", "complete:":
            self = .close
        default:
            return nil
        }
    }
}
