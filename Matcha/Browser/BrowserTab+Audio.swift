import OSLog
import WebKit

/// Son de la page (tâche 5.10) : icône haut-parleur de la barre latérale et pause d'un clic.
extension BrowserTab {
    /// La page joue un son (d'après son script de son, `PageAudio`) : icône haut-parleur sur sa ligne, son morceau de
    /// split ou sa tuile de favori ; jamais mise en veille (tâche 5.6).
    var isPlayingAudio: Bool {
        audio.isPlaying
    }

    /// Clic sur l'icône : met en pause tous les médias de la page (`pauseAllMediaPlayback`), puis éteint l'icône. La
    /// page (ou l'utilisateur, dans la page) peut relancer la lecture : l'icône revient. Jamais appelé d'office.
    func pauseAudio() {
        guard let webView else {
            return
        }
        Logger.browser.info("Son de la page mis en pause")
        webView.pauseAllMediaPlayback { [weak self, weak webView] in
            // Vue libérée ou remplacée entre-temps : son icône a déjà été éteinte.
            guard let self, let webView, self.webView === webView else {
                return
            }
            audio.reset()
        }
    }
}
