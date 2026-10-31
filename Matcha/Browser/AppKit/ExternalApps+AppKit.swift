import AppKit

extension ExternalApps {
    /// Side of the app icon asked of the system, in pixels: sharp in the banner (20 points) on a Retina screen.
    private static let iconSide = 64.0

    /// The Mac's apps, through `NSWorkspace`.
    static var system: ExternalApps {
        ExternalApps(
            open: { NSWorkspace.shared.open($0) },
            handler: { url in
                NSWorkspace.shared.urlForApplication(toOpen: url).map { app in
                    var rect = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
                    return ExternalApp(
                        name: FileManager.default.displayName(atPath: app.path),
                        icon: NSWorkspace.shared.icon(forFile: app.path).cgImage(forProposedRect: &rect, context: nil, hints: nil),
                    )
                }
            },
        )
    }
}
