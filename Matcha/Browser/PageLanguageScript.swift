import WebKit

/// Reads the language of a page once it has loaded (task 9.3), in the translation script's isolated world: its `lang`
/// attribute and the start of its text (code, styles and fields left out), for `PageLanguage`. Main frame only.
@MainActor
enum PageLanguageScript {
    static func sample(in webView: WKWebView) async throws -> PageLanguageSample? {
        let result = try await webView.callAsyncJavaScript(
            source,
            arguments: ["maximumLength": PageLanguageSample.maximumLength],
            in: nil,
            contentWorld: PageTranslationScript.world,
        )
        return PageLanguageSample(scriptResult: result)
    }

    static let source = """
    const root = document.body;
    if (!root) {
        return { lang: document.documentElement.lang ?? '', text: '' };
    }
    const excluded = 'script, style, noscript, template, textarea, select, pre, code, svg, math';
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode: (node) => node.parentElement?.closest(excluded) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
    });
    let text = '';
    for (let node = walker.nextNode(); node && text.length < maximumLength; node = walker.nextNode()) {
        const piece = node.data.trim();
        if (piece) {
            text += piece + ' ';
        }
    }
    return { lang: document.documentElement.lang ?? '', text: text.slice(0, maximumLength) };
    """
}
