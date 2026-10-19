import SwiftUI

/// Message placed over a page whose process stopped several times in a row (task 5.7): it no longer reloads by
/// itself. The button, like ⌘R, reloads it. Same style as the welcome view of an empty tab; it covers the page (card
/// of a pane, peek, mini window) and takes its clicks.
struct PageProblemView: View {
    let page: BrowserTab
    /// Makes the page active (pane of a split) when the message or its button is clicked.
    var activate: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(
                    "This page had a problem",
                    comment: "Title of the message shown in place of a page whose content stopped working several times in a row",
                )
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            // The site, without the full address.
            Text(verbatim: AddressDisplay.short(for: page.url))
        } actions: {
            Button("Reload") { page.reload() }
                .accessibilityIdentifier("pageProblemReloadButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
        // Like the address bar of a pane: a click makes the page active, without taking the button's own click.
        .simultaneousGesture(TapGesture().onEnded { activate() })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pageProblem")
    }
}
