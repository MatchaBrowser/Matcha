import Foundation
@testable import Matcha
import Testing
import WebKit

/// Extension pages inside web pages (like Bitwarden's menu in fields): a web-accessible extension page, embedded
/// by a content script, loads and runs with the extensions API. The scheme stays WebKit's: those of Safari, Chrome
/// and Firefox do not load in the web pages of another app (`DECISIONS.md`).
@MainActor
@Suite(.webKit)
struct ExtensionPageFramesTests {
    /// Manifest V2 extension: its content script adds the `frame.html` iframe, which announces its scheme to the page.
    private func makeExtension() throws -> URL {
        WKWebExtension.MatchPattern.registerCustomURLScheme(TestPages.scheme)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FramesExtension-\(UUID().uuidString)",
            isDirectory: true,
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Frames",
            "version": "1.0",
            "background": ["page": "background.html"],
            "content_scripts": [["matches": ["obtest://*/*"], "js": ["content.js"], "run_at": "document_end"]],
            "web_accessible_resources": ["frame.html", "frame.js"],
            "permissions": ["obtest://*/*"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let files: [String: String] = [
            "background.html": "<p>background</p>",
            "content.js": """
            window.addEventListener("message", e => {
                if (typeof e.data === "string" && e.data.startsWith("frame:")) { document.documentElement.dataset.reply = e.data; }
            });
            const frame = document.createElement("iframe");
            frame.src = chrome.runtime.getURL("frame.html");
            document.body.appendChild(frame);
            """,
            "frame.html": "<script src='frame.js'></script>",
            "frame.js": """
            const api = typeof chrome !== "undefined" && !!chrome.runtime;
            window.parent.postMessage("frame: ran " + location.protocol + " api " + api, "*");
            """,
        ]
        for (name, contents) in files {
            try Data(contents.utf8).write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    @Test func `extension pages keep the WebKit scheme`() async throws {
        let manager = TestExtension.manager()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(context.baseURL.scheme == "webkit-extension")
        #expect(ExtensionManager.isExtensionURL(context.baseURL))
        manager.unload(identifier: context.uniqueIdentifier)
    }

    @Test func `an extension page embedded in a web page runs with the extension API`() async throws {
        let folder = try makeExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let model = WindowModel(session: session, defaults: nil)
        let manager = TestExtension.manager()
        manager.testWindows.windowDidAppear(model, window: nil)
        manager.testWindows.update()
        let identifier = TestExtension.uniqueIdentifier("frames")
        let context = try await manager.load(resourceBaseURL: folder, identifier: identifier)
        for pattern in context.webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        // Content scripts are only injected once the background has loaded.
        try await TestExtension.waitForBackground(of: context)
        let storeID = UUID()
        let configuration = TestPages.configuration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        manager.attach(to: configuration)
        let tab = model.space.tabManager.insertTab(configuration: configuration, after: nil, select: true)
        manager.testWindows.update()
        tab.load(TestPages.url("frames"))
        var reply = ""
        try await waitUntilAsync {
            reply = await (try? tab.loadedWebView.evaluateJavaScript("document.documentElement.dataset.reply ?? ''") as? String) ?? ""
            return !reply.isEmpty
        }
        #expect(reply == "frame: ran webkit-extension: api true")
        tab.unload(resettingTo: nil, title: nil)
        try? await WKWebsiteDataStore.remove(forIdentifier: storeID)
        manager.unload(identifier: identifier)
    }
}
