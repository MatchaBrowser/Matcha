import AppKit
@testable import Matcha
import Testing
import WebKit

/// AppKit container of the Peek page, in an offscreen window: keyboard, ⎋, size.
@MainActor
struct PeekWebContainerTests {
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )

    private var contentView: NSView {
        window.contentView!
    }

    private func makeWebView() -> WKWebView {
        WKWebView(frame: .zero, configuration: WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent()))
    }

    @Test func `the peek page takes the keyboard from the page`() {
        let page = makeWebView()
        contentView.addSubview(page)
        window.makeFirstResponder(page)
        #expect(window.firstResponder === page)

        let peekPage = makeWebView()
        contentView.addSubview(PeekWebContainer(webView: peekPage))
        #expect(window.firstResponder === peekPage)
    }

    @Test func `the peek page leaves the keyboard to a text field`() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        contentView.addSubview(field)
        window.makeFirstResponder(field)
        let editor = window.firstResponder
        #expect(editor is NSText)

        let peekPage = makeWebView()
        contentView.addSubview(PeekWebContainer(webView: peekPage))
        #expect(window.firstResponder === editor)
        #expect(window.firstResponder !== peekPage)
    }

    @Test func `escape not kept by the page closes Peek`() {
        let container = PeekWebContainer(webView: makeWebView())
        var cancelCount = 0
        container.onCancel = { cancelCount += 1 }
        container.cancelOperation(nil)
        #expect(cancelCount == 1)
    }

    @Test func `page follows the container size until it leaves`() {
        let peekPage = makeWebView()
        let container = PeekWebContainer(webView: peekPage)
        contentView.addSubview(container)
        container.setFrameSize(NSSize(width: 300, height: 200))
        #expect(peekPage.frame == container.bounds)

        let card = NSView(frame: contentView.bounds)
        contentView.addSubview(card)
        card.addSubview(peekPage)
        #expect(container.subviews.isEmpty)
        container.setFrameSize(NSSize(width: 500, height: 400))
        #expect(peekPage.frame.size == NSSize(width: 300, height: 200))
    }

    @Test func `focus comes back after the page moves`() async throws {
        let peekPage = makeWebView()
        let container = PeekWebContainer(webView: peekPage)
        contentView.addSubview(container)
        #expect(window.firstResponder === peekPage)

        // Like “Open as Tab”: the keyboard is given back to the window, then the view changes parent.
        window.makeFirstResponder(nil)
        PeekFocus.focus(peekPage, awayFrom: container)
        let card = NSView(frame: contentView.bounds)
        contentView.addSubview(card)
        card.addSubview(peekPage)

        try await Task.sleep(for: .milliseconds(200))
        #expect(window.firstResponder === peekPage)
    }
}
