import OSLog
import WebKit

/// Arrêt du processus d'une page (tâche 5.7) : plantage, ou processus arrêté par le système (mémoire). Page visible
/// (onglet sélectionné ou panneau de son split dans le Space affiché d'une fenêtre ouverte, aperçu, mini-fenêtre) :
/// rechargée tout de suite ; cachée : rechargée quand on l'affiche ; arrêts répétés : un message dans la page, qui
/// n'est rechargée que par l'utilisateur. Règles : `PageCrashPolicy` ; ce que fait l'onglet : `BrowserTab+Crash`.
extension NavigationCoordinator {
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tabHost, let page = tabHost.page(for: webView) else {
            Logger.browser.notice("Processus d'une page inconnue arrêté")
            return
        }
        let terminations = page.crash.processDidTerminate(at: now())
        let action = PageCrashPolicy.action(isVisible: tabHost.isVisible(page), recentTerminations: terminations)
        // Jamais l'adresse : l'hôte seulement.
        let host = page.url?.host() ?? "?"
        let window = Int(PageCrashCounter.window)
        Logger.browser.error("""
        Processus de la page arrêté (\(host, privacy: .private)) : \(terminations, privacy: .public) fois en \
        \(window, privacy: .public) s, \(action.rawValue, privacy: .public)
        """)
        page.webContentProcessDidTerminate(action)
    }
}
