import AppKit

extension NSWindow {
    /// True if a sheet can open on this window now: visible, without a sheet already.
    var canPresentSheet: Bool {
        isVisible && attachedSheet == nil
    }
}

extension NSAlert {
    /// As a sheet on `window` if it can take one, otherwise as its own window (review CO4); `completion` gets the
    /// button chosen.
    func present(in window: NSWindow?, completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        if let window, window.canPresentSheet {
            beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(runModal())
        }
    }
}
