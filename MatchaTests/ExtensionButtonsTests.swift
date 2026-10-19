import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// Extension buttons (task 6.5): which ones to show, hidden button remembered, action (title, badge, popover) and
/// popover anchor.
@MainActor
struct ExtensionButtonsTests {
    /// Test extension with an action (title, popup) and a background that sets a “7” badge.
    private func loadExtensionWithAction(in manager: ExtensionManager) async throws -> (identifier: String, folder: URL) {
        let folder = try TestExtension.makeFolder()
        let manifestURL = folder.appendingPathComponent("manifest.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["action"] = ["default_title": "Matcha Test Action", "default_popup": "popup.html"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        try Data("<p>Popup</p>".utf8).write(to: folder.appendingPathComponent("popup.html"))
        // A second later: once the test holds the action and its revision, so that the update comes after them.
        try Data(#"setTimeout(() => browser.action.setBadgeText({ text: "7" }), 1000);"#.utf8)
            .write(to: folder.appendingPathComponent("test-extension-background.js"))
        let identifier = TestExtension.uniqueIdentifier("buttons")
        try await manager.load(resourceBaseURL: folder, identifier: identifier)
        return (identifier, folder)
    }

    @Test func `loaded extensions have a button unless hidden, private windows only when allowed`() async throws {
        let manager = TestExtension.manager()
        let (context, folder) = try await TestExtension.load(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        let identifier = try #require(manager.identifier(of: context))

        #expect(manager.toolbar.buttonExtensions(isPrivate: false).map(\.identifier) == [identifier])
        #expect(manager.toolbar.buttonExtensions(isPrivate: true).isEmpty)
        manager.setAccessToPrivateData(true, identifier: identifier)
        #expect(manager.toolbar.buttonExtensions(isPrivate: true).map(\.identifier) == [identifier])

        let revision = manager.toolbar.buttonsRevision
        manager.toolbar.setShowsButton(false, identifier: identifier)
        #expect(manager.toolbar.buttonsRevision != revision)
        #expect(!manager.toolbar.showsButton(identifier))
        #expect(manager.toolbar.buttonExtensions(isPrivate: false).isEmpty)
        // Remembered, even when WebKit changes the decisions or on reload.
        manager.saveAllStates()
        manager.unload(identifier: identifier)
        #expect(manager.store.state(for: identifier)?.showsButton == false)
        try await manager.load(resourceBaseURL: folder, identifier: identifier)
        #expect(manager.toolbar.buttonExtensions(isPrivate: false).isEmpty)

        manager.toolbar.setShowsButton(true, identifier: identifier)
        #expect(manager.store.state(for: identifier)?.showsButton == nil)
        #expect(manager.toolbar.buttonExtensions(isPrivate: false).map(\.identifier) == [identifier])
        manager.unload(identifier: identifier)
    }

    @Test func `an action gives its title, popup and badge`() async throws {
        let manager = TestExtension.manager()
        let (identifier, folder) = try await loadExtensionWithAction(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        let action = try #require(manager.toolbar.action(of: identifier, for: nil))
        #expect(action.label == "Matcha Test Action")
        #expect(action.presentsPopup)

        let revision = manager.toolbar.actionRevision
        try await TestExtension.waitForBackground(of: #require(manager.contexts[identifier]))
        try await waitUntil { manager.toolbar.action(of: identifier, for: nil)?.badgeText == "7" }
        // WebKit reports the update a little after the badge changes.
        try await waitUntil { manager.toolbar.actionRevision != revision }
        manager.unload(identifier: identifier)
    }

    @Test func `the popup is anchored under the button of its extension`() async throws {
        let manager = TestExtension.manager()
        let (identifier, folder) = try await loadExtensionWithAction(in: manager)
        defer { try? FileManager.default.removeItem(at: folder) }
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true,
        )
        let button = NSView(frame: CGRect(x: 10, y: 10, width: 26, height: 26))
        window.contentView?.addSubview(button)
        manager.testWindows.buttonAnchors.register(button, identifier: identifier, tabID: nil)
        let action = try #require(manager.toolbar.action(of: identifier, for: nil))

        let anchor = try #require(manager.testWindows.popups.anchor(action, window))
        #expect(anchor.view === button)
        #expect(anchor.rect == button.bounds)

        // Without a button (hidden): top right corner of the window.
        manager.testWindows.buttonAnchors.unregister(button)
        #expect(manager.testWindows.popups.anchor(action, window)?.view === window.contentView)
        manager.unload(identifier: identifier)
    }

    @Test func `anchors prefer the button of the targeted tab, in the right window`() {
        let anchors = ExtensionButtonAnchors()
        let first = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let second = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let tab = UUID()
        let left = NSView()
        let right = NSView()
        let elsewhere = NSView()
        first.contentView?.addSubview(left)
        first.contentView?.addSubview(right)
        second.contentView?.addSubview(elsewhere)
        anchors.register(left, identifier: "ext", tabID: UUID())
        anchors.register(right, identifier: "ext", tabID: tab)
        anchors.register(elsewhere, identifier: "ext", tabID: tab)

        #expect(anchors.view(for: "ext", tabID: tab, in: first) === right)
        #expect(anchors.view(for: "ext", tabID: tab, in: second) === elsewhere)
        #expect(anchors.view(for: "other", tabID: tab, in: first) == nil)
        anchors.unregister(right)
        #expect(anchors.view(for: "ext", tabID: tab, in: first) === left)
    }

    // MARK: Native messages

    @Test func `native message replies are spaced per extension`() {
        var throttle = NativeMessageThrottle()
        let start = ContinuousClock.now
        #expect(throttle.delay(for: "bitwarden", at: start) == .zero)
        // Loop: the next message, right away, waits one second, then one more.
        #expect(throttle.delay(for: "bitwarden", at: start) == .seconds(1))
        #expect(throttle.delay(for: "bitwarden", at: start + .milliseconds(500)) == .milliseconds(1500))
        // Another extension does not wait.
        #expect(throttle.delay(for: "proton", at: start) == .zero)
        // Long afterwards: immediate again.
        #expect(throttle.delay(for: "bitwarden", at: start + .seconds(10)) == .zero)
    }

    @Test func `native messages are refused with an error`() async throws {
        let manager = TestExtension.manager()
        let folder = try TestExtension.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifestURL = folder.appendingPathComponent("manifest.json")
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        manifest["action"] = ["default_title": "Native"]
        manifest["permissions"] = ["nativeMessaging"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let script = """
        browser.runtime.sendNativeMessage("com.example.app", { command: "sleep" })
            .then(() => browser.action.setBadgeText({ text: "ok" }))
            .catch(() => browser.action.setBadgeText({ text: "err" }));
        """
        try Data(script.utf8).write(to: folder.appendingPathComponent("test-extension-background.js"))
        let identifier = TestExtension.uniqueIdentifier("native")
        let context = try await manager.load(resourceBaseURL: folder, identifier: identifier)
        context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        try await TestExtension.waitForBackground(of: context)
        try await waitUntil { manager.toolbar.action(of: identifier, for: nil)?.badgeText == "err" }
        manager.unload(identifier: identifier)
    }
}
