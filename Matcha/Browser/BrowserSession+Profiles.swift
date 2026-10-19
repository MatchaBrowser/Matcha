import Foundation
import OSLog
import SwiftData
import WebKit

/// Creating, renaming and deleting profiles.
extension BrowserSession {
    /// Creates a profile and its first Space; returns the Space.
    @discardableResult
    func addProfile(named name: String) -> SpaceSession {
        let context = container.mainContext
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = profiles.count + 1
        let profile = ProfileRecord(
            name: trimmed.isEmpty ? String(localized: "Profile \(number)", comment: "Default name of a new profile") : trimmed,
            order: (profiles.map(\.order).max() ?? -1) + 1,
        )
        context.insert(profile)
        save(context)
        refreshProfiles()
        return addSpace(in: profile)
    }

    /// Renames the profile; an empty name keeps the old one.
    func renameProfile(_ profile: ProfileRecord, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        profile.name = trimmed
        save(container.mainContext)
    }

    /// The profile's Spaces, in the bar's order.
    func spaces(of profile: ProfileRecord) -> [SpaceSession] {
        spaces.filter { $0.record.profile?.id == profile.id }
    }

    /// Deletes the profile, its Spaces, its favorites, its website data (cookies, storage), its permission decisions
    /// and its history.
    /// The last profile cannot be deleted.
    func deleteProfile(_ profile: ProfileRecord) async {
        guard let identifier = removeProfile(profile) else {
            return
        }
        await removeWebsiteData(ofProfile: identifier)
    }

    /// Deletes the profile, its Spaces, its favorites, its permission decisions and its history; returns its
    /// identifier, or nil if it is the last profile. Its website data still has to be erased (`removeWebsiteData`).
    func removeProfile(_ profile: ProfileRecord) -> UUID? {
        guard profiles.count > 1, profiles.contains(where: { $0.id == profile.id }) else {
            return nil
        }
        // Its sign-in windows (task 5.8) close first, so their pages stop using its data.
        popupWindows.closeWindows(using: dataStore(for: profile))
        for space in spaces(of: profile) {
            space.close()
            removeSpace(space)
            container.mainContext.delete(space.record)
        }
        let identifier = profile.id
        container.mainContext.delete(profile)
        save(container.mainContext)
        refreshProfiles()
        forgetDataStore(of: identifier)
        favoritesHolders[identifier] = nil
        sitePermissions.removeAll(profileID: identifier)
        history?.removeAll(profileID: identifier)
        return identifier
    }

    /// Erases the website data (cookies, storage) of a deleted profile.
    func removeWebsiteData(ofProfile identifier: UUID) async {
        guard !isInMemory else {
            return
        }
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
        } catch {
            // A web view was still using it: it will be deleted at the next launch.
            Logger.app
                .notice("Données du profil supprimé gardées jusqu'au prochain lancement : \(error.logSummary, privacy: .public)")
        }
    }
}
