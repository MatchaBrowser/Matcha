import SwiftUI

/// Back, forward, reload (or stop) for the tab, then Home if requested.
/// The container chooses the button style.
struct NavigationButtons: View {
    let tab: BrowserTab?
    var showsHistoryButtons = true
    /// Action of the Home button; nil to hide it.
    var goHome: (() -> Void)?

    var body: some View {
        if showsHistoryButtons {
            Button("Back", systemImage: "arrow.left") { tab?.goBack() }
                .disabled(tab?.canGoBack != true)
            Button("Forward", systemImage: "arrow.right") { tab?.goForward() }
                .disabled(tab?.canGoForward != true)
            if tab?.isLoading == true {
                Button("Stop", systemImage: "xmark") { tab?.stop() }
            } else {
                Button("Reload", systemImage: "arrow.clockwise") { tab?.reload() }
                    .disabled(tab?.url == nil)
            }
        }
        if let goHome {
            Button("Home", systemImage: "house", action: goHome)
                .accessibilityIdentifier("homeButton")
        }
    }
}
