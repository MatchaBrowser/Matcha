import OSLog
import WebKit

/// The page's sound (task 5.10): speaker icon in the sidebar and one-click pause.
extension BrowserTab {
    /// The page is playing sound (according to its audio script, `PageAudio`): speaker icon on its row, its split
    /// piece or its favorite tile; never put to sleep (task 5.6).
    var isPlayingAudio: Bool {
        audio.isPlaying
    }

    /// Click on the icon: pauses all of the page's media (`pauseAllMediaPlayback`), then turns the icon off. The page
    /// (or the user, in the page) can resume playback: the icon comes back. Never called automatically.
    func pauseAudio() {
        guard let webView else {
            return
        }
        Logger.browser.info("Son de la page mis en pause")
        webView.pauseAllMediaPlayback { [weak self, weak webView] in
            // View released or replaced in the meantime: its icon has already been turned off.
            guard let self, let webView, self.webView === webView else {
                return
            }
            audio.reset()
        }
    }
}
