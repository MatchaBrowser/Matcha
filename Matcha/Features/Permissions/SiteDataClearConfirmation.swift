import SwiftUI
import WebKit

/// Effacement des cookies et données d'un site, demandé depuis le panneau des réglages du site (tâche 5.2) : l'onglet
/// et son site au moment du clic.
struct SiteDataClearRequest {
    let tab: BrowserTab
    let origin: SiteOrigin

    /// Efface les données du site dans le magasin du profil de l'onglet (fenêtre privée : le sien), puis recharge la
    /// page.
    func perform() async {
        let store = tab.webView?.configuration.websiteDataStore ?? tab.configuration.websiteDataStore
        await WebsiteDataCleaner.removeData(forHost: origin.host, in: store)
        tab.reload()
    }
}

/// Confirmation de l'effacement, posée sur la fenêtre et non sur le panneau : la barre latérale flottante (barre
/// masquée), qui porte le panneau, disparaît dès que le pointeur la quitte pour aller vers l'alerte, et l'alerte avec.
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
            Text(
                "You will be signed out of this website. The page will reload.",
                comment: "Site settings: confirmation message before clearing the data of one website",
            )
        }
    }
}
