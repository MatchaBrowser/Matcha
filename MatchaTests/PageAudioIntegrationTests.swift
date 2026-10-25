import Foundation
@testable import Matcha
import Testing
import WebKit

/// Sound of a real page (task 5.10): the script in its isolated world, its messages, the icon, and pausing through
/// `pauseAllMediaPlayback`. The pages play silence (`AudioTestPages`), in an offscreen window.
@MainActor
struct PageAudioIntegrationTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let window = AudioTestWindow()

    /// Selected tab, in the window, once `url` is loaded (title `title`).
    private func show(_ url: URL, title: String) async throws -> BrowserTab {
        let configuration = TestPages.configuration()
        // These pages play on their own: no click, which Matcha waits for before media with sound (audit H5).
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let tab = manager.insertTab(configuration: configuration, after: nil, select: true)
        window.show(tab.loadedWebView)
        tab.load(url)
        try await waitUntil { tab.title == title && !tab.isLoading }
        return tab
    }

    private func evaluate(_ script: String, in tab: BrowserTab, arguments: [String: Any] = [:]) async throws -> Any? {
        try await tab.loadedWebView.callAsyncJavaScript(script, arguments: arguments, contentWorld: .page)
    }

    /// True if the page's `son` element moves forward during half a second (it loops: any change counts).
    private func isAdvancing(_ webView: WKWebView) async throws -> Bool {
        let script = "return document.getElementById('son').currentTime"
        let start = try await webView.callAsyncJavaScript(script, contentWorld: .page) as? Double
        try await Task.sleep(for: .milliseconds(500))
        let end = try await webView.callAsyncJavaScript(script, contentWorld: .page) as? Double
        return start != end
    }

    /// Waits until the page's `son` element plays (even muted).
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

        // Without waiting for the delay (very long here): the icon turns off as soon as WebKit has paused the page.
        tab.audio.silenceDelay = 600
        tab.pauseAudio()
        try await waitUntil { !tab.isPlayingAudio }
        #expect(try await evaluate("return document.getElementById('son').paused", in: tab) as? Bool == true)
        // Nothing plays anymore: the script says nothing more (otherwise it would repeat it every 2 s).
        try await Task.sleep(for: .seconds(2.5))
        #expect(!tab.isPlayingAudio)

        // The page (or the user, in the page) resumes playback: the icon comes back.
        _ = try await evaluate("document.getElementById('son').play(); return true", in: tab)
        try await waitUntil { tab.isPlayingAudio }
    }

    /// Review WB9: a page that stops the media events before they reach the document still lights the icon.
    @Test func `a page can't hide its sound by stopping the events`() async throws {
        let types = "['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange']"
        let stop = "window.addEventListener(type, (e) => e.stopImmediatePropagation(), true)"
        let blind = "<script>for (const type of \(types)) { \(stop); }</script>"
        let tab = try await show(TestPages.url("musique", body: blind + AudioTestPages.audio()), title: "musique")
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

    /// Closing a tab stops its page without waiting for its web view to be freed: a view still held elsewhere (here,
    /// by the window) goes silent, and its page can no longer play.
    @Test func `a closed tab goes silent even if its web view lives on`() async throws {
        let tab = try await show(AudioTestPages.playingPage(), title: "musique")
        try await waitUntilPlaying(tab)
        let webView = tab.loadedWebView
        manager.close(tab)
        #expect(!tab.isLoaded)
        #expect(!tab.isPlayingAudio)
        // WebKit suspends the page's media asynchronously, in its process; once paused, the position settles once.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while try await isAdvancing(webView) {
            guard clock.now < deadline else {
                throw WaitTimeoutError(line: #line)
            }
        }

        _ = try await webView.callAsyncJavaScript("document.getElementById('son').play(); return true", contentWorld: .page)
        #expect(try await !isAdvancing(webView))
    }

    @Test func `leaving the page puts the icon out at once`() async throws {
        let tab = try await show(AudioTestPages.playingPage(), title: "musique")
        try await waitUntil { tab.isPlayingAudio }

        // Without waiting for the delay (very long here): the page has changed (`didCommit`).
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

        // The iframe goes away: its sound stops with it.
        _ = try await evaluate("document.getElementById('cadre').remove(); return true", in: tab)
        try await waitUntil { !tab.isPlayingAudio }
    }

    /// The script repeats every 2 s that it is playing: the icon recovers if the app has cleared its state.
    @Test func `a page still playing after a reset lights the icon again`() async throws {
        let tab = try await show(AudioTestPages.playingPage(), title: "musique")
        try await waitUntil { tab.isPlayingAudio }
        tab.audio.reset()
        #expect(!tab.isPlayingAudio)
        try await waitUntil { tab.isPlayingAudio }
    }
}
