import Foundation

/// What needs to be known about a server response to decide whether it is displayed or downloaded.
nonisolated struct DownloadResponse: Equatable, Sendable {
    /// True if WebKit can display this content type (`WKNavigationResponse.canShowMIMEType`).
    var canShowMIMEType: Bool
    /// `Content-Disposition` header, if there is one.
    var contentDisposition: String?
    /// HTTP status code; nil outside HTTP (local file, `data:`, app scheme).
    var statusCode: Int?
}

extension DownloadResponse {
    /// Response as WebKit gives it (`WKNavigationResponse.response`): header and status code read if it comes from
    /// an HTTP server. A response from an app scheme (`WKURLSchemeHandler`) arrives without headers.
    nonisolated init(_ response: URLResponse, canShowMIMEType: Bool) {
        let http = response as? HTTPURLResponse
        self.init(
            canShowMIMEType: canShowMIMEType,
            contentDisposition: http?.value(forHTTPHeaderField: "Content-Disposition"),
            statusCode: http?.statusCode,
        )
    }
}

/// Download rules (task 5.1), without UI dependency.
nonisolated enum DownloadPolicy {
    /// Responses without content: nothing to display or download, the page stays displayed.
    static let noContentStatusCodes: Set<Int> = [204, 205]

    /// A response is downloaded if WebKit cannot display it, or if the server serves it as an attachment.
    /// Also applies to a subframe: that is how some sites start a download.
    static func shouldDownload(_ response: DownloadResponse) -> Bool {
        if let status = response.statusCode, noContentStatusCodes.contains(status) {
            return false
        }
        return !response.canShowMIMEType || isAttachment(response.contentDisposition)
    }

    /// True if the `Content-Disposition` header announces an attachment: its type, before the first `;`, is
    /// `attachment`, ignoring case and spaces; the parameters (`filename=…`) are ignored.
    /// Like WebKit (Safari), another type (`inline`, unknown type, malformed header) lets the page display.
    static func isAttachment(_ contentDisposition: String?) -> Bool {
        guard let contentDisposition, let type = contentDisposition.split(separator: ";", omittingEmptySubsequences: false).first
        else {
            return false
        }
        return type.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("attachment") == .orderedSame
    }
}
