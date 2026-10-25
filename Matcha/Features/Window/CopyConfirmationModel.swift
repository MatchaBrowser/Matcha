import AppKit
import Observation
import OSLog

/// “URL Copied” confirmation of a window: visible for 1.5 s after each copy. A new copy while it is displayed
/// restarts the wait; closing the window cancels it.
@MainActor
@Observable
final class CopyConfirmationModel {
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// Display duration, fades not included.
    nonisolated static let displayDuration = Duration.milliseconds(1500)

    private(set) var isVisible = false
    /// Confirmed copies: each one is announced to VoiceOver, even when the confirmation is already visible.
    private(set) var presentationCount = 0

    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// `sleep` is replaced in tests.
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Shows the confirmation and restarts the wait before hiding it.
    /// Copies `url` (as a URL and as text), then confirms: the same in a browser window and in a mini window (review
    /// CO4).
    func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        TabLinkCopier.copy(url, to: pasteboard)
        show()
        // Never the address itself.
        Logger.browser.info("Address copied")
    }

    func show() {
        hideTask?.cancel()
        isVisible = true
        presentationCount += 1
        let sleep = sleep
        hideTask = Task { [weak self] in
            do {
                try await sleep(Self.displayDuration)
            } catch {
                // Cancelled: more recent copy or window closed.
                return
            }
            // A wait that ignores cancellation must not hide the next confirmation.
            guard !Task.isCancelled, let self else {
                return
            }
            isVisible = false
            hideTask = nil
        }
    }

    /// Window closed: hides immediately and stops the wait.
    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
    }
}
