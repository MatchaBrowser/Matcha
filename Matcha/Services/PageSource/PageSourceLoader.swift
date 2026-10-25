import Foundation

/// Reads the source code of a page for “View Page Source” and Save As > Page Source, off the main thread: a local file
/// (regular file only), or the site's response with the profile's cookies (ephemeral session, presented as Safari).
/// Never more than `maximumSize` bytes. Without UI dependency, but not pure: it reads the disk and the network.
nonisolated enum PageSourceLoader {
    enum Failure: LocalizedError, Equatable {
        case tooLarge
        case notAFile

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                String(localized: "The source of this page is too large to be shown.", comment: "Page source viewer, error")
            case .notAFile:
                String(localized: "This address isn't a file.", comment: "Page source viewer, error for a local address")
            }
        }
    }

    /// Largest source read (a web page is rarely over a few megabytes).
    static let maximumSize = 32 * 1024 * 1024
    /// Longest wait for the whole response.
    static let timeout: TimeInterval = 60

    /// Content of `page` and its encoding; `cookies`: those of the page's profile (only the ones for its address are
    /// sent).
    @concurrent
    static func load(_ page: URL, cookies: [HTTPCookie], userAgent: String) async throws -> (Data, String?) {
        if page.isFileURL {
            return try (readFile(page), nil)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeout
        if let storage = configuration.httpCookieStorage {
            storage.cookieAcceptPolicy = .always
            cookies.forEach(storage.setCookie)
        }
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(from: page)
        do {
            let data = try await BoundedRead.data(of: bytes, expectedLength: response.expectedContentLength, limit: maximumSize)
            return (data, response.textEncodingName)
        } catch is BoundedRead.TooLarge {
            throw Failure.tooLarge
        }
    }

    /// Content of a regular file of at most `maximumSize` bytes (never a device such as `/dev/zero`).
    static func readFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw Failure.notAFile
        }
        guard (values.fileSize ?? 0) <= maximumSize else {
            throw Failure.tooLarge
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Page that shows the source of `data`, or the error.
    @concurrent
    static func viewerHTML(for result: Result<(Data, String?), any Error>, title: String) async -> String {
        switch result {
        case let .success((data, encoding)):
            return PageSource.viewerHTML(source: PageSource.text(of: data, textEncodingName: encoding), title: title)
        case let .failure(error):
            let message = String(localized: "The source of this page couldn't be loaded.", comment: "Page source viewer, after an error")
            return PageSource.errorHTML(title: title, message: message, detail: error.localizedDescription)
        }
    }
}
