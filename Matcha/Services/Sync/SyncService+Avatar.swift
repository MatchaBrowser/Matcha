import CryptoKit
import Foundation
import OSLog

/// Avatar of the sync account (`SYNC.md` § 3.5 and § 4.4): an image encrypted on this Mac with the account's data key,
/// that the server keeps as an opaque content. Kept in cache with its date, downloaded again only when the account
/// announces another one; unreadable, the default avatar is shown, without deleting anything.
extension SyncService {
    /// Signed in to a server that keeps the account's avatar; otherwise the setting is hidden.
    var supportsAvatar: Bool {
        isActive && configuration.serverInfo?.hasAvatar == true
    }

    /// Largest image the server accepts.
    var maximumAvatarBytes: Int {
        configuration.serverInfo?.maximumAvatarImageBytes ?? 256 * 1024
    }

    /// Reads the account: the avatar is downloaded again if its date changed, forgotten if there is none. An answer
    /// that comes after a change of account is dropped (review SY24); an avatar that can't be read shows the default
    /// one, and isn't downloaded again until another one is announced (review SY37).
    func refreshAvatar() async {
        guard supportsAvatar, let (client, accountKey) = try? signedInAccount(), let accountID = configuration.accountID else {
            return
        }
        let isCurrent = { [weak self] in self?.client === client && self?.configuration.accountID == accountID && !Task.isCancelled }
        avatarCheckedAt = .now
        do {
            let account = try await client.account()
            guard isCurrent() else {
                return
            }
            guard let description = account.avatar else {
                forgetAvatar()
                return
            }
            let isKnown = description.updatedAt == configuration.avatarUpdatedAt && avatar != nil
            guard !isKnown, description.updatedAt != configuration.unreadableAvatarAt || description.updatedAt == nil else {
                return
            }
            let limit = configuration.serverInfo?.maximumAvatarBytes ?? SyncServerInfo(api: 1).maximumAvatarBytes
            let encrypted = try await client.avatar(limit: limit)
            guard isCurrent() else {
                return
            }
            guard let encrypted else {
                forgetAvatar()
                return
            }
            do {
                let dataKey = SyncAccountKeys.dataKey(accountKey: accountKey)
                let image = try SyncCrypto.decryptAvatar(
                    encrypted,
                    accountID: accountID,
                    keyVersion: SyncServerTransport.keyVersion,
                    dataKey: dataKey,
                )
                keepAvatar(image, updatedAt: description.updatedAt)
            } catch {
                Logger.sync.error("Unreadable avatar: \(error.logSummary, privacy: .public)")
                forgetAvatar()
                configuration.unreadableAvatarAt = description.updatedAt
                configuration.save(to: defaults)
            }
        } catch {
            Logger.sync.error("Avatar not read: \(error.logSummary, privacy: .public)")
        }
    }

    /// Replaces the account's avatar with `image` (JPEG or PNG), or deletes it (nil); a failed replacement leaves the
    /// previous one in place.
    func setAvatar(_ image: Data?) async throws {
        let (client, accountKey) = try signedInAccount()
        guard let accountID = configuration.accountID else {
            throw SyncClientError.signedOut
        }
        guard let image else {
            try await client.deleteAvatar()
            forgetAvatar()
            return
        }
        let dataKey = SyncAccountKeys.dataKey(accountKey: accountKey)
        let encrypted = try SyncCrypto.encryptAvatar(
            image,
            accountID: accountID,
            keyVersion: SyncServerTransport.keyVersion,
            dataKey: dataKey,
        )
        let description = try await client.putAvatar(encrypted)
        keepAvatar(image, updatedAt: description.updatedAt)
    }

    func forgetAvatar() {
        setAvatar(nil)
        configuration.avatarUpdatedAt = nil
        if let url = avatarCacheURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func keepAvatar(_ image: Data, updatedAt: Date?) {
        setAvatar(image)
        configuration.avatarUpdatedAt = updatedAt
        configuration.unreadableAvatarAt = nil
        configuration.save(to: defaults)
        if let url = avatarCacheURL {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? image.write(to: url, options: .atomic)
        }
    }

    /// Cache of the avatar, next to the sync states.
    var avatarCacheURL: URL? {
        directory?.appendingPathComponent("avatar")
    }
}
