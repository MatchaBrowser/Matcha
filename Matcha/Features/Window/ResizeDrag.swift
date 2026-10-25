import Foundation

/// A drag of a resizing handle (sidebar width, split divider): the value at its start, kept until the drag ends, even
/// a cancelled one, which SwiftUI reports only through a `@GestureState` going back to its initial value (review
/// ON25). Pure type.
nonisolated struct ResizeDrag<Value: Sendable>: Sendable {
    private(set) var start: Value?

    /// The value at the start of the drag: `current` at its first change, the same one until `end`.
    mutating func begin(at current: Value) -> Value {
        if let start {
            return start
        }
        start = current
        return current
    }

    /// The drag ended or was cancelled: the next one starts from the value of that moment.
    mutating func end() {
        start = nil
    }
}
