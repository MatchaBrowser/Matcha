import Foundation
@testable import Matcha
import Testing

/// Review ON26: the name of a folder being renamed is selected only if its field has the keyboard.
@MainActor
struct FolderNameSelectionTests {
    private struct Cancelled: Error {}

    /// Counts the focus requests and the selections; `focusTaken`: what the field reports afterwards.
    private final class Field {
        var focusRequests = 0
        var selections = 0
        var focusTaken = true
    }

    private func run(_ field: Field, cancelledAfter sleeps: Int? = nil) async {
        var count = 0
        await FolderNameSelection.run(
            sleep: { _ in
                count += 1
                if let sleeps, count > sleeps {
                    throw Cancelled()
                }
            },
            focus: { field.focusRequests += 1 },
            isFocused: { field.focusTaken },
            selectAll: { field.selections += 1 },
        )
    }

    @Test func `the name is selected once the field has the keyboard`() async {
        let field = Field()
        await run(field)
        #expect(field.focusRequests == 1)
        #expect(field.selections == 1)
    }

    @Test func `a field gone before the end selects nothing`() async {
        let beforeFocus = Field()
        await run(beforeFocus, cancelledAfter: 0)
        #expect(beforeFocus.focusRequests == 0 && beforeFocus.selections == 0)
        let afterFocus = Field()
        await run(afterFocus, cancelledAfter: 1)
        #expect(afterFocus.focusRequests == 1 && afterFocus.selections == 0)
    }

    /// The selection would go to the page, which has the keyboard.
    @Test func `a field without the keyboard selects nothing`() async {
        let field = Field()
        field.focusTaken = false
        await run(field)
        #expect(field.selections == 0)
    }
}
