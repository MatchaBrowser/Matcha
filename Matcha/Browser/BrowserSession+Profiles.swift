import Foundation
import OSLog
import SwiftData
import WebKit

/// Création, renommage et suppression des profils.
extension BrowserSession {
    /// Crée un profil et son premier Space ; renvoie le Space.
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

    /// Renomme le profil ; un nom vide garde l'ancien.
    func renameProfile(_ profile: ProfileRecord, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        profile.name = trimmed
        save(container.mainContext)
    }

    /// Spaces du profil, dans l'ordre de la barre.
    func spaces(of profile: ProfileRecord) -> [SpaceSession] {
        spaces.filter { $0.record.profile?.id == profile.id }
    }

    /// Supprime le profil, ses Spaces, ses favoris, ses données de sites (cookies, stockage), ses décisions de
    /// permission et son historique.
    /// Le dernier profil ne peut pas être supprimé.
    func deleteProfile(_ profile: ProfileRecord) async {
        guard profiles.count > 1, profiles.contains(where: { $0.id == profile.id }) else {
            return
        }
        // Ses fenêtres de connexion (tâche 5.8) se ferment d'abord : leurs pages n'utilisent plus ses données.
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
        sitePermissions.removeAll(profileID: identifier)
        history?.removeAll(profileID: identifier)
        guard !isInMemory else {
            return
        }
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: identifier)
        } catch {
            // Une vue web l'utilisait encore : il sera supprimé au prochain lancement.
            Logger.app
                .notice("Données du profil supprimé gardées jusqu'au prochain lancement : \(error.localizedDescription, privacy: .public)")
        }
    }
}
