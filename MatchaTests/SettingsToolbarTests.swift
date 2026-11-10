import AppKit
@testable import Matcha
import Testing

/// The settings' toolbar shows all its tabs, in each language: a tab that doesn't fit goes into an overflow menu (»)
/// where SwiftUI shows it greyed, impossible to choose. SwiftUI lays that toolbar out like `NSTabViewController`'s
/// (style `.toolbar`, window `.preference`): the same names in the same width tell which tabs fit. Checked against
/// the real window: at 520 points, the English toolbar of 9 tabs kept 7 of them, as this measure does.
@MainActor
struct SettingsToolbarTests {
    @Test(arguments: LocalizationTests.languages)
    func `every tab fits in the toolbar`(language: String) throws {
        let titles = try SettingsSelection.Tab.allCases.map { try Self.title(of: $0, in: language) }
        #expect(Self.visibleTabs(titles, width: SettingsView.width) == titles.count, "\(language): \(titles)")
    }

    @Test func `the measure sees the tabs that don't fit`() {
        let titles = SettingsSelection.Tab.allCases.map(\.title.key)
        #expect(Self.visibleTabs(titles, width: 400) < titles.count)
    }

    /// The name of the tab as the app's language shows it; English, the source language, is the key itself.
    private static func title(of tab: SettingsSelection.Tab, in language: String) throws -> String {
        let key = tab.title.key
        guard language != LocalizationTests.sourceLanguage else {
            return key
        }
        let folder = try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
        let bundle = try #require(Bundle(url: folder))
        return bundle.localizedString(forKey: key, value: nil, table: "Localizable")
    }

    /// How many tabs the toolbar shows, in a window whose content is `width` points wide.
    private static func visibleTabs(_ titles: [String], width: CGFloat) -> Int {
        let controller = NSTabViewController()
        controller.tabStyle = .toolbar
        for (title, tab) in zip(titles, SettingsSelection.Tab.allCases) {
            let content = NSViewController()
            content.view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
            let item = NSTabViewItem(viewController: content)
            item.label = title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)
            controller.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        window.alphaValue = 0
        window.setContentSize(NSSize(width: width, height: 200))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        window.displayIfNeeded()
        return window.toolbar?.visibleItems?.count { !$0.label.isEmpty } ?? 0
    }
}
