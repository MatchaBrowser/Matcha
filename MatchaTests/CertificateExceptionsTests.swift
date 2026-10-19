import Foundation
@testable import Matcha
import Security
import Testing
import WebKit

/// “Visit This Website Anyway” after a certificate error (audit K5): that certificate, that website, until the app
/// quits; the page then says “Not Secure”.
@MainActor
struct CertificateExceptionsTests {
    /// Two self-signed certificates made for these tests (`openssl req -x509`, EC P-256), with no key kept.
    private static let first =
        "MIIBizCCATGgAwIBAgIUF0zeg3GGJHWFbGYHnAxhZpHeFtowCgYIKoZIzj0EAwIwGzEZMBcGA1UEAwwQZXNzYWktdW4uZXhh" +
        "bXBsZTAeFw0yNjEwMTkwOTI3NTZaFw0zNjEwMTYwOTI3NTZaMBsxGTAXBgNVBAMMEGVzc2FpLXVuLmV4YW1wbGUwWTATBgcq" +
        "hkjOPQIBBggqhkjOPQMBBwNCAASsConyEYwT2XDjcCJR3YpJ/vSTiplnrGEQJNmaq2xWWkZUeLAo1FV/USyLbREusl+KkDpo" +
        "cL+R861/CqSHRpjKo1MwUTAdBgNVHQ4EFgQUNZTzTTlxn79jJVp/v2N/6yIvxKswHwYDVR0jBBgwFoAUNZTzTTlxn79jJVp/" +
        "v2N/6yIvxKswDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiEAtW4D8F3lJtl6Z1aO4Us/Pykwr+Wv7jK1XBUK" +
        "SKTMn38CIEuvt9S4T+5LmMOY/+t3SKXIAfYhSSB6le9fmS1yJdLM"
    private static let second =
        "MIIBkDCCATWgAwIBAgIUS2+yv5rxuiVq3d3DfduaAtsJEfMwCgYIKoZIzj0EAwIwHTEbMBkGA1UEAwwSZXNzYWktZGV1eC5l" +
        "eGFtcGxlMB4XDTI2MTAxOTA5Mjc1NloXDTM2MTAxNjA5Mjc1NlowHTEbMBkGA1UEAwwSZXNzYWktZGV1eC5leGFtcGxlMFkw" +
        "EwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEbWTPYSXLTu/ueLrkt6SCmniD3pSB5MrpFu+zXqMYGyl79WbEHw6/qNtAZXvYQzya" +
        "fOqZ7HiHSuHKmadbvbGfTqNTMFEwHQYDVR0OBBYEFHlMujz0Hk7qzxscYJPQfnrKPSBdMB8GA1UdIwQYMBaAFHlMujz0Hk7q" +
        "zxscYJPQfnrKPSBdMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAMM16Tlkne+Vc8mnuHqdL43OMVDvnyUj" +
        "UQjXyHLgl02vAiEA0A+Z5z6rtabgYB4IeDz5rhiBz38wIgO0nFHEIRywDXE="

    private let site = URL(string: "https://expire.example/")!

    @Test func `an exception holds for that certificate and that website only`() throws {
        let exceptions = CertificateExceptions()
        let first = try Self.trust(Self.first)
        let second = try Self.trust(Self.second)
        #expect(!exceptions.isAccepted(first, host: "expire.example"))

        exceptions.accept(first, host: "Expire.example")
        #expect(exceptions.isAccepted(first, host: "expire.example"))
        #expect(!exceptions.isAccepted(second, host: "expire.example"))
        #expect(!exceptions.isAccepted(first, host: "autre.example"))
        // Nothing is kept for the next launch.
        #expect(!CertificateExceptions().isAccepted(first, host: "expire.example"))
    }

    @Test func `visit anyway accepts the certificate and loads the page again`() throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        _ = tab.loadedWebView
        let trust = try Self.trust(Self.first)
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateHasBadDate, userInfo: [
            NSURLErrorFailingURLErrorKey: site,
            NSURLErrorFailingURLPeerTrustErrorKey: trust,
        ])
        // Without a place to record the exception, no way through.
        tab.provisionalLoadDidFail(error)
        #expect(tab.loadFailure.error?.kind == .certificate)
        #expect(!tab.loadFailure.canVisitAnyway)

        let exceptions = CertificateExceptions()
        tab.provisionalLoadDidFail(error, certificateExceptions: exceptions)
        #expect(tab.loadFailure.canVisitAnyway)
        tab.visitDespiteInvalidCertificate()
        #expect(exceptions.isAccepted(trust, host: "expire.example"))
        #expect(tab.loadFailure.error == nil)
        #expect(tab.displayedURL == site)
    }

    @Test func `a website visited despite its certificate is not secure`() async throws {
        let manager = TabManager(websiteDataStore: .nonPersistent())
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.loadedWebView.loadSimulatedRequest(URLRequest(url: site), responseHTML: "<title>expire</title>")
        try await waitUntil { tab.displayedURL == site && !tab.isLoading }
        #expect(tab.security != .invalidCertificate)

        tab.acceptedCertificateHosts.insert("expire.example")
        #expect(tab.security == .invalidCertificate)
        #expect(tab.security.hasCertificate)
    }

    private static func trust(_ base64: String) throws -> SecTrust {
        let data = try #require(Data(base64Encoded: base64))
        let certificate = try #require(SecCertificateCreateWithData(nil, data as CFData))
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, "expire.example" as CFString), &trust) ==
            errSecSuccess)
        return try #require(trust)
    }
}
