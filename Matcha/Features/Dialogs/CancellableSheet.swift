import AppKit

/// A page's sheet that ends when its task is cancelled: the page went or changed document (review IU15). The page then
/// gets no answer, as for “Cancel”.
@MainActor
enum CancellableSheet {
    /// The response of `sheet`, begun on `window` by `begin`; nil if the task was cancelled.
    static func response(
        of sheet: NSWindow,
        on window: NSWindow,
        _ begin: () async -> NSApplication.ModalResponse,
    ) async -> NSApplication.ModalResponse? {
        let handle = SheetHandle(sheet: sheet, window: window)
        let response = await withTaskCancellationHandler {
            await begin()
        } onCancel: {
            Task { @MainActor in handle.end() }
        }
        return Task.isCancelled ? nil : response
    }
}

/// The sheet to end, without keeping it or its window.
@MainActor
private final class SheetHandle {
    weak var sheet: NSWindow?
    weak var window: NSWindow?

    init(sheet: NSWindow, window: NSWindow) {
        self.sheet = sheet
        self.window = window
    }

    func end() {
        if let sheet, let window {
            window.endSheet(sheet, returnCode: .abort)
        }
    }
}
