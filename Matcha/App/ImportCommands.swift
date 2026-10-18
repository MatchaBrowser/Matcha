import SwiftUI

/// Fichier > Importer depuis > Arc… (tâche 7.1), comme le menu de Safari. Grisé hors d'une fenêtre de navigation et
/// dans une fenêtre privée.
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
