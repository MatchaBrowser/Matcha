import AppKit
import SwiftUI

/// Matcha > About Matcha: the standard panel, with the version of this build (`AboutVersion`). AppKit still reads the
/// credits from `Credits.rtf`.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Matcha") {
                let version = AboutVersion.current()
                NSApp.orderFrontStandardAboutPanel(options: [
                    .applicationVersion: version.applicationVersion,
                    .version: version.build,
                ])
            }
        }
    }
}
