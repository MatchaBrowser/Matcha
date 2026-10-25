import OSLog
import WebKit

/// JavaScript dialogs and files to send (audits K1 and K2): shown by `dialogs`, as sheets on the page's window, with
/// the website of the frame that asks. From a page's second dialog on, the user can stop the others until the next
/// document (Safari's defense against a page that loops on `alert`).
extension NavigationCoordinator {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        _ = await presentDialog(.alert, message: message, frame: frame, in: webView)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> Bool {
        await presentDialog(.confirm, message: message, frame: frame, in: webView)?.isConfirmed ?? false
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> String? {
        let answer = await presentDialog(.prompt(defaultText: defaultText ?? ""), message: prompt, frame: frame, in: webView)
        return answer?.isConfirmed == true ? answer?.text ?? "" : nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame _: WKFrameInfo,
    ) async -> [URL]? {
        guard tabHost?.page(for: webView) != nil else {
            return nil
        }
        return await dialogs.chooseFiles(
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories,
            for: webView,
        )
    }

    private func presentDialog(
        _ kind: PageDialog.Kind,
        message: String,
        frame: WKFrameInfo,
        in webView: WKWebView,
    ) async -> PageDialogAnswer? {
        guard let page = tabHost?.page(for: webView), !page.pageDialogs.isSuppressed else {
            return nil
        }
        let site = frame.securityOrigin.siteOrigin?.displayName
        let dialog = PageDialog(
            kind: kind,
            message: message,
            site: site,
            isFromEmbeddedFrame: !frame.isMainFrame,
            offersSuppression: page.pageDialogs.shown > 0,
        )
        page.pageDialogs.didShow()
        let answer = await dialogs.present(dialog, for: webView)
        if answer?.suppressesFurther == true {
            page.pageDialogs.suppress()
            Logger.browser.info("Page dialogs stopped by the user")
        }
        return answer
    }
}
