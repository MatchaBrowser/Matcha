import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

/// État d'une fenêtre : le Space affiché, le bord par lequel arrive le Space choisi (animation), la
/// confirmation « URL copiée », la liste des téléchargements, le panneau des réglages du site et celui de la
/// personnalisation d'un dossier.
@MainActor
@Observable
final class WindowModel {
    static let currentSpaceKey = "currentSpaceID"

    let session: BrowserSession
    private(set) var currentSpaceID: UUID?
    private(set) var transitionEdge = Edge.trailing
    /// Confirmation montrée à chaque adresse copiée depuis cette fenêtre.
    let copyConfirmation = CopyConfirmationModel()
    /// Panneau des téléchargements ouvert (tâche 5.1), par le bouton du pied de la barre ou ⌥⌘L ; seul l'utilisateur
    /// l'ouvre et le ferme. Barre masquée, il réapparaît avec la barre flottante.
    var isDownloadsPresented = false
    /// Panneau des réglages du site ouvert (tâche 5.2), pour l'onglet affiché ; seul l'utilisateur l'ouvre et le ferme.
    var isSiteSettingsPresented = false
    /// Effacement des données d'un site en attente de confirmation (alerte de la fenêtre).
    var siteDataClearRequest: SiteDataClearRequest?
    /// Dossier d'épinglés dont le panneau de personnalisation est ouvert, sous sa ligne : un seul par fenêtre. Seul
    /// l'utilisateur l'ouvre et le ferme (menu du dossier, ×, Échap) ; il ne se voit que dans le Space du dossier.
    var customizedFolderID: UUID?
    /// Space dont l'éditeur (bulle de son icône, au pied de la barre) est ouvert. Tenu ici et non par la vue : changer
    /// de Space recrée la barre latérale (`.id` du Space), qui perdrait son état avant d'ouvrir la bulle.
    var editedSpaceID: UUID?
    /// Import depuis Arc lancé de cette fenêtre (tâche 7.1).
    let arcImport = ArcImportModel()
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

    /// Affiche `target`, qui reprend et tient désormais les favoris de son profil.
    func select(_ target: SpaceSession) {
        let current = space
        guard target !== current, let targetIndex = session.spaces.firstIndex(where: { $0 === target }) else {
            return
        }
        // Les onglets affichés (tout le split) quittent l'écran : ils retiennent leur état de navigation ; leur
        // aperçu se ferme.
        current.tabManager.displayedTabs.forEach { $0.captureInteractionState() }
        current.tabManager.closePeek()
        // Il reprend les favoris de son profil, tenus jusque-là par un autre Space.
        session.showFavorites(in: target)
        transitionEdge = targetIndex > spaceIndex ? .trailing : .leading
        // La bulle d'un Space ne survit pas à un changement de Space (sauf `editSpace`, qui la rouvre).
        editedSpaceID = nil
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

    /// « Changer l'icône… » et « Modifier le thème… » du menu d'un Space : l'affiche et ouvre son éditeur.
    func editSpace(_ target: SpaceSession) {
        select(target)
        editedSpaceID = target.id
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

    /// « Personnaliser… » du menu d'un dossier : ouvre son panneau (fermant celui d'un autre dossier), ou le ferme s'il
    /// est déjà ouvert.
    func toggleFolderCustomization(_ folderID: UUID) {
        customizedFolderID = customizedFolderID == folderID ? nil : folderID
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
