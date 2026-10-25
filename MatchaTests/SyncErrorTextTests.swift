import Foundation
@testable import Matcha
import Testing

/// Messages of the sync errors (review TS12): written by Matcha from the error's code, one per kind of error. Compared
/// with each other, never with a text: the tests run in this Mac's language.
@MainActor
struct SyncErrorTextTests {
    private let fallback = SyncErrorText.message(forCode: SyncServerError.serverError)

    @Test(arguments: [
        SyncServerError.invalidCredentials, SyncServerError.registrationClosed, SyncServerError.invitationRequired,
        SyncServerError.emailTaken, SyncServerError.weakKDF, SyncServerError.rateLimited, SyncServerError.unsupportedClient,
        SyncServerError.quotaExceeded, SyncServerError.unavailable, SyncServerError.deviceRevoked,
        SyncServerError.accountDeleted, SyncServerError.invalidToken, SyncServerError.tokenExpired,
    ])
    func `each code the client knows has its message`(code: String) {
        #expect(SyncErrorText.message(forCode: code) != fallback)
        #expect(SyncErrorText.message(for: SyncServerError(status: 400, code: code)) == SyncErrorText.message(forCode: code))
    }

    @Test func `an unknown code says the server had a problem`() {
        #expect(SyncErrorText.message(for: SyncServerError(status: 500, code: "something_new")) == fallback)
    }

    @Test func `an untrusted certificate says why, other network errors say the server can't be reached`() {
        let certificate = Set([
            URLError.Code.serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid, .secureConnectionFailed,
        ].map { SyncErrorText.message(for: URLError($0)) })
        #expect(certificate.count == 1)
        let unreachable = SyncErrorText.message(for: URLError(.cannotConnectToHost))
        #expect(!certificate.contains(unreachable))
        #expect(SyncErrorText.message(for: URLError(.timedOut)) == unreachable)
        #expect(
            SyncErrorText.message(for: URLError(.appTransportSecurityRequiresSecureConnection))
                == SyncErrorText.message(for: SyncServerAddress.Problem.insecure),
        )
        #expect(SyncErrorText.message(for: SyncServerAddress.Problem.invalid) != SyncErrorText
            .message(for: SyncServerAddress.Problem.insecure))
    }

    @Test func `client errors each have their message`() {
        let errors: [SyncClientError] = [
            .notASyncServer,
            .unreadableAnswer,
            .signedOut,
            .accountKeyUnreadable,
            .keychain(errSecInteractionNotAllowed),
        ]
        #expect(Set(errors.map(SyncErrorText.message(for:))).count == errors.count)
    }

    /// Only weak parameters blame the server: a recovery key that doesn't open the account is not its fault.
    @Test func `a key that doesn't open is not the server's security`() {
        let weak = SyncErrorText.message(for: SyncCryptoError.weakKDF)
        #expect(SyncErrorText.message(for: SyncServerError(status: 400, code: SyncServerError.weakKDF)) == weak)
        #expect(SyncErrorText.message(for: SyncCryptoError.passwordTooShort) != weak)
        let unreadable = SyncErrorText.message(for: SyncClientError.accountKeyUnreadable)
        #expect(SyncErrorText.message(for: SyncCryptoError.invalidRecoveryKey) == unreadable)
        #expect(SyncErrorText.message(for: SyncCryptoError.unreadable) == unreadable)
        #expect(SyncErrorText.message(for: SyncCryptoError.keyDerivationFailed) != weak)
    }
}
