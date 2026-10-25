import Foundation
@testable import Matcha
import Testing
import WebKit

/// Downloads a page starts on its own (audit W7): a second one, or one from a frame inside the page, waits for the
/// user in the banner, unless it follows a real click or the user allowed it.
@MainActor
@Suite(.webKit)
struct DownloadConsentTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let now = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func `the first download of a page goes, the next ones and frames' ones ask`() {
        func needs(allowed: Bool = false, click: Date? = nil, subframe: Bool = false, earlier: Int = 0) -> Bool {
            DownloadConsentPolicy.needsConsent(
                isAllowed: allowed,
                lastClick: click,
                now: now,
                isSubframe: subframe,
                earlierDownloads: earlier,
            )
        }
        #expect(!needs())
        #expect(needs(earlier: 1))
        #expect(needs(subframe: true))
        #expect(!needs(click: now.addingTimeInterval(-4), subframe: true, earlier: 3))
        #expect(needs(click: now.addingTimeInterval(-6), earlier: 1))
        #expect(!needs(allowed: true, subframe: true, earlier: 3))
    }

    @Test func `downloads without a click wait for the banner, and allow lets the page's next ones through`() throws {
        let (page, recorder) = try openPage()

        download(in: page, recorder: recorder)
        #expect(recorder.policies == [.download])

        // A second one without a click, then a third while the banner waits: both wait for the same answer.
        download(in: page, recorder: recorder)
        download(in: page, recorder: recorder)
        #expect(recorder.policies == [.download])
        #expect(page.permissionPrompts.currentAction?.action == .downloadFiles)
        #expect(page.permissionPrompts.actions.count == 1)

        page.permissionPrompts.answerAction(.allowOnce)
        #expect(recorder.policies == [.download, .download, .download])
        download(in: page, recorder: recorder)
        #expect(recorder.policies.count == 4)
        #expect(page.permissionPrompts.currentAction == nil)
    }

    @Test func `a refused or abandoned download is cancelled`() throws {
        let (page, recorder) = try openPage()
        download(in: page, recorder: recorder)
        download(in: page, recorder: recorder)
        page.permissionPrompts.answerAction(.decline)
        #expect(recorder.policies == [.download, .cancel])

        download(in: page, recorder: recorder)
        page.permissionPrompts.denyAll()
        #expect(recorder.policies == [.download, .cancel, .cancel])
    }

    @Test func `a real click downloads without asking`() throws {
        let (page, recorder) = try openPage()
        download(in: page, recorder: recorder)
        download(in: page, recorder: recorder, button: 1)
        #expect(recorder.policies == [.download, .download])
        #expect(page.permissionPrompts.currentAction == nil)
    }

    private func openPage() throws -> (BrowserTab, PolicyRecorder) {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        _ = tab.loadedWebView
        manager.coordinator.now = { now }
        return (tab, PolicyRecorder())
    }

    /// A `download` link clicked: by the page's script (button 0) or by the user (button 1).
    private func download(in page: BrowserTab, recorder: PolicyRecorder, button: Int = 0) {
        let action = FakeNavigationAction(
            url: URL(string: "data:text/plain,fichier")!,
            modifierFlags: [],
            buttonNumber: button,
            shouldPerformDownload: true,
        )
        manager.coordinator.webView(page.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
    }
}
