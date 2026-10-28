import AppKit
import OSLog
import WebKit

/// Translation in the menu of a page (task 9.3), as in Chrome: “Translate to ‹target›”, then “Translate to Another
/// Language” › the languages the Mac can translate into (the one chosen becomes the target); “Show Original” on a
/// translated page. Enabled on a web page or a local file, in a window that can translate it.
extension BrowserWebView {
    func translationMenuItems(showsImage: Bool) -> [NSMenuItem] {
        let translation = (uiDelegate as? any PageMenuDelegate)?.pageMenuTranslation(in: self)
        let main = menuItem(for: .translate, showsImage: showsImage)
        let translatable = translationHost != nil && Self.isTranslatable(backForwardList.currentItem?.url)
        if translation?.isTranslated == true {
            main.title = String(localized: "Show Original")
            main.isEnabled = true
            return [main]
        }
        let pageLanguage = translation?.pageLanguage
        let isPageLanguage = { (language: Locale.Language) in pageLanguage.map { PageLanguage.isSame($0, language) } ?? false }
        let target = translationHost?.targetLanguage
        if let target {
            main.title = String(
                localized: "Translate to \(TranslationLanguageName.inSentence(target))",
                comment: "Context menu of a web page: translates it; %@ is a language as written in a sentence (“French”, “français”)",
            )
            main.isEnabled = translatable && !isPageLanguage(target)
        }
        let others = (translationHost?.languageChoices ?? []).filter { language in
            !isPageLanguage(language) && !(target.map { PageLanguage.isSame($0, language) } ?? false)
        }
        guard translatable, !others.isEmpty else {
            return [main]
        }
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for language in others {
            let item = NSMenuItem(title: TranslationLanguageName.of(language), action: #selector(performTranslation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.minimalIdentifier
            submenu.addItem(item)
        }
        let more = NSMenuItem(title: String(localized: "Translate to Another Language"), action: nil, keyEquivalent: "")
        more.identifier = NSUserInterfaceItemIdentifier(PageCommand.translate.identifier + "Other")
        more.submenu = submenu
        return [main, more]
    }

    private static func isTranslatable(_ url: URL?) -> Bool {
        url?.scheme.map { ["http", "https", "file"].contains($0.lowercased()) } ?? false
    }

    @objc private func performTranslation(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String else {
            return
        }
        (uiDelegate as? any PageMenuDelegate)?.pageMenu(translateInto: Locale.Language(identifier: identifier), in: self)
        Logger.browser.info("Page menu: Translate to another language")
    }
}
