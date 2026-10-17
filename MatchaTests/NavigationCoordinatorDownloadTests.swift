import Foundation
@testable import Matcha
import Testing
import WebKit

/// Le coordinateur et les téléchargements (tâche 5.1) : liens `download`, rattachement des téléchargements à leur
/// fenêtre. Les réponses se testent par `DownloadPolicyTests` (un `WKNavigationResponse` créé à la main fait planter
/// WebKit à sa libération) et de bout en bout par `DownloadIntegrationTests`.
@MainActor
struct NavigationCoordinatorDownloadTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    @Test func `download link becomes a download, even with command`() throws {
        let recorder = PolicyRecorder()
        let webView = manager.newTab().loadedWebView
        let url = try #require(URL(string: "https://example.com/fichier.zip"))
        let action = FakeNavigationAction(url: url, modifierFlags: .command, shouldPerformDownload: true)

        manager.coordinator.webView(webView, decidePolicyFor: action) { recorder.record($0) }

        #expect(recorder.policies == [.download])
        #expect(manager.tabs.count == 1)
    }

    @Test func `downloads go to the shared list by default`() {
        #expect(manager.coordinator.downloadManager === DownloadManager.shared)
        #expect(manager.downloadScope == .regular)
    }

    @Test func `private sessions have their own scope, for every Space`() {
        let first = BrowserSession.makePrivate()
        let second = BrowserSession.makePrivate()
        #expect(first.downloadScope != .regular)
        #expect(first.downloadScope != second.downloadScope)
        #expect(first.spaces.allSatisfy { $0.tabManager.downloadScope == first.downloadScope })
        #expect(first.addSpace(inProfileOf: nil).tabManager.downloadScope == first.downloadScope)
    }

    @Test func `regular sessions use the regular scope`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        #expect(session.downloadScope == .regular)
        #expect(session.spaces.allSatisfy { $0.tabManager.downloadScope == .regular })
        #expect(MiniWindowManager.forTests(session: session).downloadScope == .regular)
    }
}
