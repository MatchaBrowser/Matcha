import AppKit
import CryptoKit
import Foundation

/// What starting sync at launch needs: the account kept in the keychain, and another try once the keychain opens.
extension SyncService {
    /// The account kept in the keychain: its key and its tokens; nil if one is missing.
    func storedCredentials(server: SyncServerAddress, accountID: UUID) throws -> (accountKey: SymmetricKey, tokens: SyncRefreshResponse)? {
        guard let accountKey = try keychain.data(for: .accountKey, server: server, accountID: accountID),
              let access = try keychain.data(for: .accessToken, server: server, accountID: accountID).flatMap({ String(
                  bytes: $0,
                  encoding: .utf8,
              ) }),
              let refresh = try keychain.data(for: .refreshToken, server: server, accountID: accountID).flatMap({ String(
                  bytes: $0,
                  encoding: .utf8,
              ) })
        else {
            return nil
        }
        return (SymmetricKey(data: accountKey), SyncRefreshResponse(accessToken: access, refreshToken: refresh))
    }

    /// The keychain refused at launch (locked): sync starts again when the app becomes active (review SY22).
    func startAgainOnActivation() {
        guard activationObserver == nil else {
            return
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session else {
                    return
                }
                self.stopWaitingForActivation()
                if !self.isActive {
                    self.start(session: session)
                }
            }
        }
    }

    func stopWaitingForActivation() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}
