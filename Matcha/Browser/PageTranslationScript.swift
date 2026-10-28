import OSLog
import WebKit

/// Translation script (task 9.2), run in the main frame of a page, in an isolated world (`WKContentWorld`) only when the
/// page is translated: the page neither sees it nor can call it. It cuts the page into blocks (`TranslationBlock`): a
/// block is the text of an element shown on screen up to the next block-level element or line break, its pieces are
/// its text nodes. Text the user types, code blocks and hidden text are left out; inline code, `translate="no"` and
/// `.notranslate` stay in their sentence, unchanged. Blocks on screen come first. It writes the translations into the
/// nodes, keeps their original text (the page's own changes become the new original) and puts it back on request. A
/// `MutationObserver` reads what the page adds or changes afterwards, then tells the app (at most every 500 ms, no
/// content in the message), which comes back for it.
@MainActor
enum PageTranslationScript {
    static let world = WKContentWorld.world(name: "MatchaTranslation")
    static let handlerName = "matchaTranslation"

    /// Hooks the recipient of the script's messages onto `controller` (once per configuration: WebKit refuses a second
    /// recipient with the same name). The script itself only runs when a page is translated.
    static func install(in controller: WKUserContentController) {
        controller.add(PageTranslationMessageHandler(), contentWorld: world, name: handlerName)
    }

    /// The next blocks of the page to translate, on screen first.
    static func collect(in webView: WKWebView) async throws -> PageTranslationBatch? {
        let result = try await run("collect(maximum, maximumLength)", in: webView, arguments: [
            "maximum": TranslationLimits.maximumBlocksPerCollect,
            "maximumLength": TranslationLimits.maximumPieceLength,
        ])
        return PageTranslationBatch(scriptResult: result)
    }

    /// Writes `texts` (the texts of each block's pieces) into the page.
    static func apply(_ texts: [TranslationBlock.ID: [String]], in webView: WKWebView) async throws {
        let translations = Dictionary(uniqueKeysWithValues: texts.map { (String($0.key), $0.value) })
        _ = try await run("apply(translations)", in: webView, arguments: ["translations": translations])
    }

    /// Puts the original texts back and stops reading the page's changes.
    static func restore(in webView: WKWebView) async throws {
        _ = try await run("restore()", in: webView)
    }

    private static func run(_ call: String, in webView: WKWebView, arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(
            source + "\nreturn matchaTranslation.\(call);",
            arguments: arguments,
            in: nil,
            contentWorld: world,
        )
    }

    /// Defines `matchaTranslation` once per document, in the script's world.
    static let source = #"""
    globalThis.matchaTranslation ??= (() => {
        // Text never read: not the page's text, or text the user types.
        const excluded = 'script, style, noscript, template, textarea, input, select, pre, svg, math, iframe, object, '
            + 'canvas, video, audio, [contenteditable]:not([contenteditable="false"])';
        // Text kept as it is, inside its sentence.
        const keptElements = 'code, kbd, samp, var, tt, .notranslate';
        const maximumPieces = \#(TranslationLimits.maximumPiecesPerBlock);
        const letter = /\p{L}/u;
        const handler = window.webkit?.messageHandlers?.\#(handlerName);
        const blocks = new Map();
        let owners = new WeakMap();
        let roots = [];
        let nextID = 1;
        let observer = null;
        let notification = 0;

        const scan = (root) => {
            const displays = new Map();
            const display = (element) => {
                if (!displays.has(element)) {
                    displays.set(element, getComputedStyle(element).display);
                }
                return displays.get(element);
            };
            const startsBlock = (element) => display(element) !== 'inline' && display(element) !== 'contents';
            // An element without a box of its own (`display: contents`) is as shown as its parent.
            const isShown = (element) => {
                while (element && display(element) === 'contents') {
                    element = element.parentElement;
                }
                return !element || (element.checkVisibility?.({ checkVisibilityCSS: true, visibilityProperty: true }) ?? true);
            };
            const blockOf = (element) => {
                while (element.parentElement && !startsBlock(element)) {
                    element = element.parentElement;
                }
                return element;
            };
            let group = null;
            const close = () => {
                const translatable = group?.nodes.some((node, index) => !group.kept[index] && letter.test(node.data));
                if (translatable && group.nodes.length <= maximumPieces) {
                    const id = nextID++;
                    const { element, nodes, kept } = group;
                    const originals = nodes.map((node) => node.data);
                    blocks.set(id, { element, nodes, kept, originals, fixed: [], state: 'pending' });
                    for (const node of group.nodes) {
                        owners.set(node, id);
                    }
                }
                group = null;
            };
            const add = (text) => {
                const parent = text.parentElement;
                if (owners.has(text) || !parent || !isShown(parent)) {
                    return;
                }
                const element = blockOf(parent);
                if (group?.element !== element) {
                    close();
                    if (!text.data.trim()) {
                        return;
                    }
                    group = { element, nodes: [], kept: [] };
                }
                group.nodes.push(text);
                group.kept.push(parent.translate === false || parent.closest(keptElements) !== null);
            };
            if (root.nodeType === Node.TEXT_NODE) {
                if (root.parentElement && !root.parentElement.closest(excluded)) {
                    add(root);
                }
                close();
                return;
            }
            if (root.nodeType !== Node.ELEMENT_NODE || root.closest(excluded)) {
                return;
            }
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
                acceptNode: (node) => node.nodeType === Node.ELEMENT_NODE && node.matches(excluded)
                    ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
            });
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                if (node.nodeType === Node.TEXT_NODE) {
                    add(node);
                } else if (node.tagName === 'BR' || startsBlock(node)) {
                    close();
                }
            }
            close();
        };

        const scanQueued = () => {
            const queued = roots;
            roots = [];
            for (const root of queued) {
                if (root.isConnected) {
                    scan(root);
                }
            }
        };

        // At most one message every 500 ms, however often the page changes.
        const notify = () => {
            if (!notification) {
                notification = setTimeout(() => {
                    notification = 0;
                    handler?.postMessage('changed');
                }, 500);
            }
        };

        const changed = (records) => {
            for (const record of records) {
                if (record.type !== 'characterData') {
                    roots.push(...record.addedNodes);
                    continue;
                }
                const block = blocks.get(owners.get(record.target));
                const index = block ? block.nodes.indexOf(record.target) : -1;
                if (index < 0) {
                    roots.push(record.target);
                } else if (block.originals[index] !== record.target.data) {
                    // The page wrote this text: it is the original now, and its block is translated again.
                    block.originals[index] = record.target.data;
                    block.state = 'pending';
                }
            }
            scanQueued();
            for (const block of blocks.values()) {
                if (block.state === 'pending') {
                    notify();
                    return;
                }
            }
        };

        const collect = (maximum, maximumLength) => {
            if (!observer) {
                const target = document.body ?? document.documentElement;
                observer = new MutationObserver(changed);
                observer.observe(target, { childList: true, subtree: true, characterData: true });
                roots.push(target);
            }
            scanQueued();
            const pending = [];
            for (const [id, block] of blocks) {
                if (block.state !== 'pending') {
                    continue;
                }
                if (!block.element.isConnected) {
                    blocks.delete(id);
                    continue;
                }
                const rect = block.element.getBoundingClientRect();
                const onScreen = rect.bottom > 0 && rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
                pending.push({ id, block, onScreen });
            }
            // Stable sort: blocks on screen first, each group in the order of the page.
            pending.sort((first, second) => Number(second.onScreen) - Number(first.onScreen));
            const chosen = pending.slice(0, maximum);
            return {
                remaining: pending.length - chosen.length,
                blocks: chosen.map(({ id, block }) => {
                    block.state = 'sent';
                    block.fixed = block.originals.map((text, index) => block.kept[index] || text.length > maximumLength);
                    const pieces = block.originals.map((text, index) => [text.length > maximumLength ? '' : text, block.fixed[index]]);
                    return { id, pieces };
                }),
            };
        };

        const apply = (translations) => {
            for (const [key, texts] of Object.entries(translations)) {
                const block = blocks.get(Number(key));
                if (!block || block.state !== 'sent' || !Array.isArray(texts) || texts.length !== block.nodes.length) {
                    continue;
                }
                block.nodes.forEach((node, index) => {
                    const text = texts[index];
                    if (!block.fixed[index] && typeof text === 'string' && node.data !== text) {
                        node.data = text;
                    }
                });
                block.state = 'done';
            }
            // Its own changes are no news for the observer.
            observer?.takeRecords();
        };

        const restore = () => {
            observer?.disconnect();
            observer = null;
            clearTimeout(notification);
            notification = 0;
            for (const block of blocks.values()) {
                block.nodes.forEach((node, index) => {
                    if (node.data !== block.originals[index]) {
                        node.data = block.originals[index];
                    }
                });
            }
            blocks.clear();
            owners = new WeakMap();
            roots = [];
        };

        return { collect, apply, restore };
    })();
    """#
}

/// Receives the messages of the translation script (new text in the page) and hands them to the translation of the
/// page that sends them (`BrowserWebView.translation`). A message from a frame other than the main one, or from a web
/// view already released by its tab, is ignored.
final class PageTranslationMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else {
            Logger.translation.notice("Translation script message from a subframe: ignored")
            return
        }
        (message.webView as? BrowserWebView)?.translation?.contentDidChange()
    }
}
