import Foundation
@testable import Matcha
import Testing
import WebKit

/// Son d'un onglet (tâche 5.10), avec des messages simulés : l'icône suit les messages, s'éteint après le délai, et
/// tout de suite quand la vue web est libérée (veille, déchargement) ou que le processus de la page s'arrête.
@MainActor
struct PageAudioTests {
    private let tab = BrowserTab(configuration: WebConfigurationFactory.makeConfiguration(websiteDataStore: .nonPersistent()))
    private let playing = PageAudioReport(frame: "main", isAudible: true)
    private let silent = PageAudioReport(frame: "main", isAudible: false)

    @Test func `the icon follows the page and goes out after the delay`() async throws {
        #expect(tab.audio.silenceDelay == 2)
        tab.audio.silenceDelay = 0.3
        tab.audio.receive(playing)
        #expect(tab.isPlayingAudio)

        let clock = ContinuousClock()
        let start = clock.now
        tab.audio.receive(silent)
        #expect(tab.isPlayingAudio)
        try await waitUntil { !tab.isPlayingAudio }
        #expect(clock.now - start >= .milliseconds(250))
    }

    @Test func `sound coming back during the delay keeps the icon`() async throws {
        tab.audio.silenceDelay = 0.3
        tab.audio.receive(playing)
        tab.audio.receive(silent)
        tab.audio.receive(playing)
        try await Task.sleep(for: .seconds(1))
        #expect(tab.isPlayingAudio)
    }

    @Test func `the web view sends its messages to the audio of its tab`() throws {
        let webView = try #require(tab.loadedWebView as? BrowserWebView)
        #expect(webView.audio === tab.audio)
    }

    @Test func `suspending the tab puts the icon out and detaches its web view`() throws {
        let webView = try #require(tab.loadedWebView as? BrowserWebView)
        tab.audio.receive(playing)
        tab.suspend(snapshot: nil)
        #expect(!tab.isPlayingAudio)
        // Un message tardif de l'ancienne vue n'atteint plus l'onglet.
        #expect(webView.audio == nil)
        // La vue recréée lui écrit de nouveau.
        let resumed = try #require(tab.loadedWebView as? BrowserWebView)
        #expect(resumed.audio === tab.audio)
    }

    @Test func `unloading the tab puts the icon out`() {
        _ = tab.loadedWebView
        tab.audio.receive(playing)
        tab.unload(resettingTo: nil, title: nil)
        #expect(!tab.isPlayingAudio)
    }

    @Test(arguments: [PageCrashAction.reload, .showProblem, .reloadWhenShown])
    func `a crashed page stops playing at once`(action: PageCrashAction) {
        _ = tab.loadedWebView
        tab.audio.receive(playing)
        tab.webContentProcessDidTerminate(action)
        #expect(!tab.isPlayingAudio)
    }

    @Test func `pausing a tab without web view does nothing`() {
        tab.audio.receive(playing)
        tab.pauseAudio()
        #expect(tab.isPlayingAudio)
    }
}
