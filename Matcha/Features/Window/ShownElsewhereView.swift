import SwiftUI

/// In place of a page shown by another window (a web view is only in one window at a time): a button takes it back.
struct ShownElsewhereView: View {
    let showHere: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Open in Another Window", comment: "Title shown in place of a page displayed by another browser window")
            } icon: {
                Image(systemName: "macwindow.on.rectangle")
            }
        } description: {
            Text("This tab is shown in another window.")
        } actions: {
            Button(action: showHere) {
                Text("Show Here", comment: "Button that moves the page of a tab shown by another window into this one")
            }
        }
        // Takes the full height, like the web view.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("shownElsewhere")
    }
}
