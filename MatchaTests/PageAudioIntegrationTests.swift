import Foundation
@testable import Matcha
import Testing
import WebKit

/// Son d'une vraie page (tâche 5.10) : le script dans son monde isolé, ses messages, l'icône et la pause par
/// `pauseAllMediaPlayback`. Les pages jouent du silence (`AudioTestPages`), dans une fenêtre hors de l'écran.
@MainActor
struct PageAudioIntegrationTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let window = AudioTestWindow()

    /// Onglet sélectionné, dans la fenêtre, une fois `url` chargée (titre `title`).
    private func show(_ url: URL, title: String) async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        window.show(tab.loadedWebView)
        tab.load(url)
        try await waitUntil { tab.title == title && !tab.isLoading }
        return tab
    }

    private func evaluate(_ script: String, in tab: BrowserTab, arguments: [String: Any] = [:]) async throws -> Any? {
        try await tab.loadedWebView.callAsyncJavaScript(script, arguments: arguments, contentWorld: .page)
    }

    /// Attend que l'élément `son` de la page joue (même coupé).
    private func waitUntilPlaying(_ tab: BrowserTab) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        let script = "const son = document.getElementById('son'); return !son.paused && son.currentTime > 0.1"
        while try await evaluate(script, in: tab) as? Bool != true {
            guard clock.now < deadline else {
                throw WaitTimeoutError(line: #line)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func `a playing page lights the icon and pausing it puts the icon out at once`() async throws {
        let tab = try await show(AudioTestPages.playingPage(), title: "musique")
        try await waitUntil { tab.isPlayingAudio }

        // Sans attendre le délai (ici très long) : l'icône s'éteint dès que WebKit a mis la page en pause.
        tab.audio.silenceDelay = 600
        tab.pauseAudio()
        try await waitUntil { !tab.isPlayingAudio }
        #expect(try await evaluate("return document.getElementById('son').paused", in: tab) as? Bool == true)
        // Plus rien ne joue : le script ne redit rien (il le redirait toutes les 2 s).
        try await Task.sleep(for: .seconds(2.5))
        #expect(!tab.isPlayingAudio)

        // La page (ou l'utilisateur, dans la page) relance la lecture : l'icône revient.
        _ = try await evaluate("document.getElementById('son').play(); return true", in: tab)
        try await waitUntil { tab.isPlayingAudio }
    }

    @Test func `a muted element or a zero volume shows no icon`() async throws {
        let tab = try await show(AudioTestPages.playingPage(attributes: "muted"), title: "musique")
        tab.audio.silenceDelay = 0.3
        try await waitUntilPlaying(tab)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!tab.isPlayingAudio)

        _ = try await evaluate("document.getElementById('son').muted = false; return true", in: tab)
        try await waitUntil { tab.isPlayingAudio }

        _ = try await evaluate("document.getElementById('son').volume = 0; return true", in: tab)
        try await waitUntil { !tab.isPlayingAudio }
    }

    @Test func `leaving the page puts the icon out at once`() async throws {
        let tab = try await show(AudioTestPages.playingPage(), title: "musique")
        try await waitUntil { tab.isPlayingAudio }

        // Sans attendre le délai (ici très long) : la page a changé (`didCommit`).
        tab.audio.silenceDelay = 600
        tab.load(TestPages.url("calme"))
        try await waitUntil { tab.title == "calme" }
        #expect(!tab.isPlayingAudio)
    }

    @Test func `an iframe from another site that plays sound lights the icon`() async throws {
        let tab = try await show(TestPages.url("hote"), title: "hote")
        tab.audio.silenceDelay = 0.3
        var components = URLComponents()
        components.scheme = TestPages.scheme
        components.host = "autre-site"
        components.path = "/cadre"
        components.queryItems = [URLQueryItem(name: "body", value: AudioTestPages.audio())]
        let frame = try #require(components.url)
        _ = try await evaluate("""
        const frame = document.createElement('iframe');
        frame.id = 'cadre';
        frame.src = src;
        document.body.append(frame);
        await new Promise((resolve) => { frame.onload = resolve; });
        return true
        """, in: tab, arguments: ["src": frame.absoluteString])
        try await waitUntil { tab.isPlayingAudio }

        // L'iframe s'en va : son son s'arrête avec elle.
        _ = try await evaluate("document.getElementById('cadre').remove(); return true", in: tab)
        try await waitUntil { !tab.isPlayingAudio }
    }

    /// Le script redit toutes les 2 s qu'il joue : l'icône se recale si l'app a effacé son état.
    @Test func `a page still playing after a reset lights the icon again`() async throws {
        let tab = try await show(AudioTestPages.playingPage(), title: "musique")
        try await waitUntil { tab.isPlayingAudio }
        tab.audio.reset()
        #expect(!tab.isPlayingAudio)
        try await waitUntil { tab.isPlayingAudio }
    }
}
