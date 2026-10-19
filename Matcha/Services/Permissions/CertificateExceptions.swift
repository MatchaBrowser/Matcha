import Foundation
import Security

/// Websites whose invalid certificate the user chose to accept (“Visit This Website Anyway” after a certificate error,
/// audit K5): only that exact certificate, for that website, until the app quits. Nothing is saved; another
/// certificate for the same website is refused again.
@MainActor
final class CertificateExceptions {
    /// Leaf certificates accepted, by website.
    private var accepted: [String: Set<Data>] = [:]

    func accept(_ trust: SecTrust, host: String) {
        guard let leaf = Self.leafCertificate(of: trust) else {
            return
        }
        accepted[host.lowercased(), default: []].insert(leaf)
    }

    func isAccepted(_ trust: SecTrust, host: String) -> Bool {
        guard let leaf = Self.leafCertificate(of: trust) else {
            return false
        }
        return accepted[host.lowercased()]?.contains(leaf) == true
    }

    private static func leafCertificate(of trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return nil
        }
        return SecCertificateCopyData(leaf) as Data
    }
}
