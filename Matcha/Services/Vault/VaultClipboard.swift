import Foundation

/// Where the vault copies a secret (`VAULT.md` § 7.5): marked concealed and transient so that clipboard managers skip
/// it, kept on this Mac (no universal clipboard), cleared after 90 seconds if it is still there, and at the lock. The
/// pasteboard itself is the platform's (`VaultClipboard+AppKit`), or a private one in tests.
@MainActor
final class VaultClipboard {
    static let lifetime: Duration = .seconds(90)

    /// Writes a secret; returns the pasteboard's change count after the write.
    private let write: (String) -> Int
    /// The current change count of the pasteboard.
    private let changeCount: () -> Int
    private let clear: () -> Void
    private var copied: Int?
    private var clearTask: Task<Void, Never>?

    init(write: @escaping (String) -> Int, changeCount: @escaping () -> Int, clear: @escaping () -> Void) {
        self.write = write
        self.changeCount = changeCount
        self.clear = clear
    }

    /// Copies a secret, cleared after `lifetime` unless something else was copied meanwhile.
    func copy(_ secret: String) {
        copied = write(secret)
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lifetime)
            guard !Task.isCancelled else {
                return
            }
            self?.forget()
        }
    }

    /// Clears the pasteboard if it still holds the secret copied last.
    func forget() {
        if let copied, copied == changeCount() {
            clear()
        }
        copied = nil
        clearTask?.cancel()
        clearTask = nil
    }
}
