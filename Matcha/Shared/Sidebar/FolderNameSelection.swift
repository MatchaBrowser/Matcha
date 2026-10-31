import Foundation

/// Selection of a folder's name, or a pinned tab's, when its renaming starts (review ON26): the field often appears
/// while a context menu is closing, so it takes the keyboard a little later, then its name is selected. Nothing is
/// selected if the field went away meanwhile (the task is cancelled) or didn't take the keyboard: the action would go
/// to the page.
@MainActor
enum FolderNameSelection {
    /// Time for the context menu to close.
    static let menuDelay = Duration.milliseconds(80)
    /// Time for the field to take the keyboard.
    static let focusDelay = Duration.milliseconds(20)

    static func run(
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        focus: () -> Void,
        isFocused: () -> Bool,
        selectAll: () -> Void,
    ) async {
        do {
            try await sleep(menuDelay)
            focus()
            try await sleep(focusDelay)
        } catch {
            return
        }
        if isFocused() {
            selectAll()
        }
    }
}
