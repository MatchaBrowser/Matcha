import AppKit

extension VaultClipboard {
    /// The Mac's general pasteboard, with the markers of nspasteboard.org that clipboard managers honor.
    static var system: VaultClipboard {
        VaultClipboard(.general)
    }

    /// Writes to `pasteboard` (tests: a pasteboard of their own).
    convenience init(_ pasteboard: NSPasteboard) {
        self.init(
            write: { secret in
                // Kept on this Mac: nothing goes through the universal clipboard.
                pasteboard.prepareForNewContents(with: .currentHostOnly)
                let item = NSPasteboardItem()
                item.setString(secret, forType: .string)
                item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
                item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
                pasteboard.writeObjects([item])
                return pasteboard.changeCount
            },
            changeCount: { pasteboard.changeCount },
            clear: { pasteboard.clearContents() },
        )
    }
}

/// Locks the vault when the Mac sleeps, its screen locks or sleeps, the user switches away, and when Matcha quits
/// (`VAULT.md` § 7.3).
@MainActor
final class VaultLockEvents {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    func start(locking vault: VaultService) {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked")),
            (NotificationCenter.default, NSApplication.willTerminateNotification),
        ]
        for (center, name) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak vault] _ in
                MainActor.assumeIsolated { vault?.lock() }
            }
            observers.append((center, observer))
        }
    }

    /// Stops watching (the app keeps one for its whole life).
    func stop() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers = []
    }
}
