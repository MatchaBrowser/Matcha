import Foundation
@testable import Matcha
import Testing
import WebKit

/// Sound of a tab (task 5.10), with simulated messages: the icon follows the messages, turns off after the delay, and
/// right away when the web view is released (suspension, unloading) or the page's process terminates.
@MainActor
@Suite(.webKit)
struct PageAudioTests {
    private let tab = BrowserTab(configuration: WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent()))
    private let playing = PageAudioReport(frame: "main", isAudible: true)
    private let silent = PageAudioReport(frame: "main", isAudible: false)

    @Test func `the icon follows the page and goes out after the delay`() async throws {
        #expect(tab.audio.silenceDelay == 2)
        // The test says when the delay has passed (review TS16).
        let delay = GatedSleep()
        tab.audio.sleep = delay.sleep
        tab.audio.receive(playing)
        #expect(tab.isPlayingAudio)

        tab.audio.receive(silent)
        try await waitUntil { delay.waitingCount == 1 }
        #expect(tab.isPlayingAudio)
        #expect(tab.audio.isSwitchOffScheduled)
        delay.open()
        try await waitUntil { !tab.isPlayingAudio }
        #expect(!tab.audio.isSwitchOffScheduled)
    }

    @Test func `sound coming back during the delay keeps the icon`() {
        tab.audio.silenceDelay = 0.3
        tab.audio.receive(playing)
        tab.audio.receive(silent)
        tab.audio.receive(playing)
        // Nothing left to switch the icon off (review TS2): no need to wait for the delay to pass.
        #expect(!tab.audio.isSwitchOffScheduled)
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
        // A late message from the old view no longer reaches the tab.
        #expect(webView.audio == nil)
        // The recreated view writes to it again.
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
