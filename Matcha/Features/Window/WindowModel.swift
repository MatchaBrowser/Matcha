import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// État d'une fenêtre : le Space affiché, le bord par lequel arrive le Space choisi (animation), la
/// confirmation « URL copiée », la liste des téléchargements et le panneau des réglages du site.
@MainActor
@Observable
final class WindowModel {
    static let currentSpaceKey = "currentSpaceID"

    let session: BrowserSession
    private(set) var currentSpaceID: UUID?
    private(set) var transitionEdge = Edge.trailing
    /// Confirmation montrée à chaque adresse copiée depuis cette fenêtre.
    let copyConfirmation = CopyConfirmationModel()
    /// Liste des téléchargements ouverte (tâche 5.1) ; la barre masquée reste affichée tant qu'elle l'est.
    var isDownloadsPresented = false
    /// Panneau des réglages du site ouvert (tâche 5.2), pour l'onglet affiché ; seul l'utilisateur l'ouvre et le ferme.
    var isSiteSettingsPresented = false
    /// Effacement des données d'un site en attente de confirmation (alerte de la fenêtre).
    var siteDataClearRequest: SiteDataClearRequest?
    /// Où retenir le Space affiché d'un lancement à l'autre ; nil pour ne rien retenir (tests).
    @ObservationIgnored private let defaults: UserDefaults?

    init(session: BrowserSession, defaults: UserDefaults?) {
        self.session = session
        self.defaults = defaults
        currentSpaceID = defaults?.string(forKey: Self.currentSpaceKey).flatMap(UUID.init(uuidString:))
    }

    /// Space affiché : celui choisi, sinon le premier.
    var space: SpaceSession {
        session.spaces.first { $0.id == currentSpaceID } ?? session.spaces[0]
    }

    var spaceIndex: Int {
        session.spaces.firstIndex { $0 === space } ?? 0
    }

    /// Onglet de `reference` et son Space, s'ils existent encore.
    func locate(_ reference: TabReference) -> (space: SpaceSession, tab: BrowserTab)? {
        guard let space = session.spaces.first(where: { $0.id == reference.spaceID }),
              let tab = space.tabManager.tab(withID: reference.tabID)
        else {
            return nil
        }
        return (space, tab)
    }

    /// Affiche `target`. S'il partage le profil du Space affiché, il en reprend les favoris.
    func select(_ target: SpaceSession) {
        let current = space
        guard target !== current, let targetIndex = session.spaces.firstIndex(where: { $0 === target }) else {
            return
        }
        // Les onglets affichés (tout le split) quittent l'écran : ils retiennent leur état de navigation ; leur
        // aperçu se ferme.
        current.tabManager.displayedTabs.forEach { $0.captureInteractionState() }
        current.tabManager.closePeek()
        if target.record.profile?.id == current.record.profile?.id {
            target.tabManager.adoptFavorites(from: current.tabManager)
        }
        transitionEdge = targetIndex > spaceIndex ? .trailing : .leading
        currentSpaceID = target.id
        defaults?.set(target.id.uuidString, forKey: Self.currentSpaceKey)
        target.tabManager.loadSelectedTab()
    }

    func selectSpace(at index: Int) {
        guard session.spaces.indices.contains(index) else {
            return
        }
        select(session.spaces[index])
    }

    /// Space voisin (glissement à deux doigts), sans boucler.
    func selectAdjacentSpace(_ direction: SpaceSwipeTracker.Direction) {
        selectSpace(at: spaceIndex + (direction == .next ? 1 : -1))
    }

    /// Envoie l'onglet du Space affiché dans `target`. Même profil : l'onglet garde sa page et son
    /// historique. Autre profil : il est recréé à partir de son adresse, avec les cookies de ce profil.
    func move(_ tab: BrowserTab, to target: SpaceSession) {
        let source = space
        guard target !== source else {
            return
        }
        if target.record.profile?.id == source.record.profile?.id {
            if let detached = source.tabManager.detach(tab) {
                target.tabManager.attach(detached)
            }
        } else {
            let url = tab.url
            source.tabManager.delete(tab)
            target.tabManager.newTab(url: url, select: false)
        }
    }

    /// Crée un Space dans le profil du Space affiché et l'affiche.
    func newSpace() {
        select(session.addSpace(inProfileOf: space))
    }

    /// Supprime `target` ; s'il était affiché, son voisin prend sa place.
    func deleteSpace(_ target: SpaceSession) {
        guard session.spaces.count > 1 else {
            return
        }
        if target === space, let index = session.spaces.firstIndex(where: { $0 === target }) {
            selectSpace(at: index == 0 ? 1 : index - 1)
        }
        session.deleteSpace(target)
    }

    /// Copie `url` (menu contextuel d'un onglet) et confirme « URL copiée » dans cette fenêtre.
    func copyLink(_ url: URL, to pasteboard: NSPasteboard = .general) {
        TabLinkCopier.copy(url, to: pasteboard)
        copyConfirmation.show()
        // Jamais l'adresse elle-même.
        Logger.browser.info("Adresse copiée")
    }

    /// ⇧⌘C et l'action « Copier l'URL » de la barre de commande : l'adresse de la page au premier plan
    /// (l'aperçu s'il est ouvert, sinon l'onglet affiché). Sans adresse, rien n'est copié ni confirmé.
    @discardableResult
    func copySelectedTabURL(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let url = space.tabManager.frontTab?.url else {
            return false
        }
        copyLink(url, to: pasteboard)
        return true
    }
}
