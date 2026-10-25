import Foundation
import Observation
import Security

/// The failed load shown in place of a page (audit K5), until the next load, a new document or “Back”.
@MainActor
@Observable
final class PageLoadFailure {
    private(set) var error: PageLoadError?
    /// Certificate of a website whose certificate isn't valid (“Show Certificate”).
    @ObservationIgnored private(set) var serverTrust: SecTrust?
    /// Where “Visit This Website Anyway” records the certificate.
    @ObservationIgnored private(set) weak var certificateExceptions: CertificateExceptions?

    /// True if the user can choose to visit the website despite its invalid certificate.
    var canVisitAnyway: Bool {
        error?.kind == .certificate && serverTrust != nil && certificateExceptions != nil
    }

    func show(_ error: PageLoadError, serverTrust: SecTrust?, certificateExceptions: CertificateExceptions?) {
        self.error = error
        self.serverTrust = serverTrust
        self.certificateExceptions = certificateExceptions
    }

    func clear() {
        error = nil
        serverTrust = nil
        certificateExceptions = nil
    }
}
