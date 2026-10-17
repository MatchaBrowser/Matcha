import AppKit
@testable import Matcha
import Testing
import WebKit

/// Réponse affichée ou téléchargée, et liens `download` (tâche 5.1).
struct DownloadPolicyTests {
    private func response(canShow: Bool = true, disposition: String? = nil, status: Int? = 200) -> DownloadResponse {
        DownloadResponse(canShowMIMEType: canShow, contentDisposition: disposition, statusCode: status)
    }

    @Test func `displayable response is shown`() {
        #expect(!DownloadPolicy.shouldDownload(response()))
    }

    @Test func `response WebKit cannot show is downloaded`() {
        #expect(DownloadPolicy.shouldDownload(response(canShow: false)))
        #expect(DownloadPolicy.shouldDownload(response(canShow: false, status: nil)))
    }

    @Test func `attachment is downloaded even if WebKit could show it`() {
        #expect(DownloadPolicy.shouldDownload(response(disposition: "attachment; filename=\"rapport.pdf\"")))
    }

    @Test func `no content response is never downloaded`() {
        #expect(!DownloadPolicy.shouldDownload(response(canShow: false, status: 204)))
        #expect(!DownloadPolicy.shouldDownload(response(canShow: false, disposition: "attachment", status: 205)))
    }

    @Test(arguments: [
        "attachment",
        "ATTACHMENT",
        "Attachment; filename=a.zip",
        "  attachment ;filename=\"a b.zip\"",
        "attachment;filename*=UTF-8''r%C3%A9sum%C3%A9.pdf",
        "attachment; filename=\"inline.pdf\"",
        "\tattachment\t; size=12",
    ])
    func `attachment header is recognized`(header: String) {
        #expect(DownloadPolicy.isAttachment(header))
    }

    @Test(arguments: [
        "",
        "inline",
        "INLINE; filename=attachment.pdf",
        "filename=attachment.zip",
        "attachments",
        "form-data; name=attachment",
        "attachment filename=a.zip",
        ";attachment",
    ])
    func `other headers are not attachments`(header: String) {
        #expect(!DownloadPolicy.isAttachment(header))
    }

    @Test func `missing header is not an attachment`() {
        #expect(!DownloadPolicy.isAttachment(nil))
    }

    // MARK: Réponse de WebKit

    private func http(_ headers: [String: String], status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.com/r")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    @Test func `headers are read from HTTP responses whatever their case`() {
        let response = DownloadResponse(http(["content-disposition": "attachment"], status: 201), canShowMIMEType: true)
        #expect(response == DownloadResponse(canShowMIMEType: true, contentDisposition: "attachment", statusCode: 201))
        #expect(DownloadPolicy.shouldDownload(response))
    }

    @Test func `inline HTTP page is shown`() {
        let response = DownloadResponse(http(["Content-Type": "text/html", "Content-Disposition": "inline"]), canShowMIMEType: true)
        #expect(!DownloadPolicy.shouldDownload(response))
    }

    @Test func `no content HTTP response is left to WebKit`() {
        #expect(!DownloadPolicy.shouldDownload(DownloadResponse(http([:], status: 204), canShowMIMEType: false)))
    }

    /// Fichier local, `data:` ou schéma de l'app : ni en-tête ni code.
    @Test func `other responses only depend on their type`() {
        let file = URLResponse(
            url: URL(fileURLWithPath: "/tmp/a.zip"),
            mimeType: "application/zip",
            expectedContentLength: 3,
            textEncodingName: nil,
        )
        #expect(DownloadResponse(file, canShowMIMEType: false) == DownloadResponse(
            canShowMIMEType: false,
            contentDisposition: nil,
            statusCode: nil,
        ))
        #expect(DownloadPolicy.shouldDownload(DownloadResponse(file, canShowMIMEType: false)))
        #expect(!DownloadPolicy.shouldDownload(DownloadResponse(file, canShowMIMEType: true)))
    }

    // MARK: Liens `download`

    private func request(
        url: String = "https://example.com/fichier.zip",
        modifiers: NSEvent.ModifierFlags = [],
        button: Int = 1,
        type: WKNavigationType = .linkActivated,
        mainFrame: Bool = true,
        handled: Bool = true,
        download: Bool = true,
    ) -> NavigationRequest {
        NavigationRequest(
            url: URL(string: url),
            navigationType: type,
            modifierFlags: modifiers,
            buttonNumber: button,
            targetsMainFrame: mainFrame,
            isSchemeHandledByWebView: handled,
            pageURL: URL(string: "https://example.com/page"),
            shouldPerformDownload: download,
        )
    }

    @Test func `download link is downloaded`() {
        #expect(NavigationPolicy.decide(request()) == .download)
    }

    /// Un onglet ou un aperçu ouvert sur un lien `download` resterait vide.
    @Test func `download link is downloaded whatever the click`() {
        #expect(NavigationPolicy.decide(request(modifiers: .command)) == .download)
        #expect(NavigationPolicy.decide(request(button: 4)) == .download)
        #expect(NavigationPolicy.decide(request(modifiers: .shift)) == .download)
    }

    @Test func `download requested by a script or a subframe is downloaded`() {
        #expect(NavigationPolicy.decide(request(type: .other)) == .download)
        #expect(NavigationPolicy.decide(request(mainFrame: false)) == .download)
        #expect(NavigationPolicy.decide(request(url: "data:text/plain,bonjour")) == .download)
    }

    @Test func `download link to another app's scheme is handed to that app`() throws {
        let url = try #require(URL(string: "mailto:moi@example.com"))
        #expect(NavigationPolicy.decide(request(url: url.absoluteString, handled: false)) == .openExternally(url))
    }

    @Test func `plain link is not downloaded`() {
        #expect(NavigationPolicy.decide(request(download: false)) == .allow)
    }
}
