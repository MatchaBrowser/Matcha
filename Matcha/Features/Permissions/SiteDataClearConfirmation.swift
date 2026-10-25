import SwiftUI
import WebKit

/// Clearing a site's cookies and data, requested from the site settings panel (task 5.2): the tab and its site at
/// the time of the click.
struct SiteDataClearRequest {
    let tab: BrowserTab
    let origin: SiteOrigin

    /// Clears the site's data in the data store of the tab's profile (private window: its own), then reloads the
    /// page.
    func perform() async {
        let store = tab.webView?.configuration.websiteDataStore ?? tab.configuration.websiteDataStore
        await WebsiteDataCleaner.removeData(forHost: origin.host, in: store)
        tab.reload()
    }
}

/// Confirmation of the clearing, attached to the window and not to the panel: the floating sidebar (sidebar
/// hidden), which holds the panel, disappears as soon as the pointer leaves it to go to the alert, and the alert
/// with it.
struct SiteDataClearConfirmation: ViewModifier {
    let model: WindowModel

    func body(content: Content) -> some View {
        content.alert(
            Text(
                "Clear cookies and website data for “\(model.siteDataClearRequest?.origin.displayName ?? "")”?",
                comment: "Site settings: confirmation title; %@ is the website",
            ),
            isPresented: Binding { model.siteDataClearRequest != nil } set: {
                if !$0 {
                    model.siteDataClearRequest = nil
                }
            },
            presenting: model.siteDataClearRequest,
        ) { request in
            Button("Clear", role: .destructive) {
                Task { await request.perform() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("""
            You will be signed out of this website; a password typed in a login sheet is kept until you quit Matcha. \
            The page will reload.
            """, comment: "Site settings: confirmation message before clearing the data of one website")
        }
    }
}
