import SwiftUI

/// File > Import From > Arc… (task 7.1), like Safari's menu. Disabled outside a browsing window and in a private
/// window.
struct ImportCommands: Commands {
    @FocusedValue(\.windowActions) private var windowActions

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Menu("Import From") {
                Button("Arc…") { windowActions?.importFromArc?() }
                    .disabled(windowActions?.importFromArc == nil)
            }
        }
    }
}
