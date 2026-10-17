import Foundation
import Observation
import OSLog
import SwiftData

/// Enregistre dans SwiftData les onglets d'un Space (épinglés, du jour, dossiers) et les favoris de
/// son profil, et les recharge au lancement.
@MainActor
final class SpaceStore {
    /// Délai entre un changement et son enregistrement : les changements rapprochés sont groupés.
    static let saveDelay = Duration.seconds(1)

    let space: SpaceRecord
    private let context: ModelContext
    private var pendingSave: Task<Void, Never>?
    /// Vrai une fois le Space supprimé : plus rien n'est enregistré.
    private var isStopped = false

    init(space: SpaceRecord, context: ModelContext) {
        self.space = space
        self.context = context
    }

    // MARK: Chargement

    /// Onglets enregistrés et leur rangement. Les onglets archivés ne sont pas rechargés.
    func load() -> (tabs: [StoredTab], layout: SidebarLayout) {
        let records = tabRecords().filter { $0.place != nil }
        var positions: [UUID: SidebarPosition] = [:]
        for record in records {
            if let place = record.place {
                positions[record.id] = SidebarPosition(place: place, order: record.order, folderID: record.folder?.id)
            }
        }
        let folders = (space.folders ?? []).map { folder in
            FolderEntry(id: folder.id, name: folder.name, isCollapsed: folder.isCollapsed, parentID: folder.parent?.id, order: folder.order)
        }
        let tabs = records.map { record in
            StoredTab(
                id: record.id,
                url: record.url,
                title: record.title,
                pinnedURL: record.pinnedURL,
                pinnedTitle: record.pinnedTitle,
                lastActivity: record.lastActivity,
                interactionState: record.interactionState,
            )
        }
        return (tabs, SidebarLayout(positions: positions, folders: folders))
    }

    // MARK: Enregistrement

    /// Enregistre `manager` une seconde après chaque changement de ce qui s'enregistre (rangement,
    /// adresses, titres, activité), tant que le store et le gestionnaire existent.
    func startAutosave(of manager: TabManager) {
        withObservationTracking {
            _ = manager.layout
            _ = manager.storedTabs()
        } onChange: { [weak self, weak manager] in
            Task { @MainActor in
                guard let self, let manager else {
                    return
                }
                self.scheduleSave(of: manager)
                self.startAutosave(of: manager)
            }
        }
    }

    /// Enregistre tout de suite (fermeture de l'app), en annulant l'enregistrement différé.
    func saveNow(_ manager: TabManager) {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isStopped else {
            return
        }
        save(tabs: manager.storedTabs(), layout: manager.layout)
    }

    /// N'enregistre plus rien (Space supprimé).
    func stop() {
        isStopped = true
        pendingSave?.cancel()
        pendingSave = nil
    }

    private func scheduleSave(of manager: TabManager) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, weak manager] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled, let self, let manager else {
                return
            }
            saveNow(manager)
        }
    }

    /// Met les enregistrements à jour : crée ce qui manque, supprime les onglets et dossiers fermés.
    /// Les onglets archivés sont conservés.
    func save(tabs: [StoredTab], layout: SidebarLayout) {
        let folders = saveFolders(layout.folderEntries)
        let positions = layout.positions
        var existing = Dictionary(tabRecords().map { ($0.id, $0) }) { first, _ in first }
        for stored in tabs {
            guard let position = positions[stored.id] else {
                continue
            }
            let record = existing.removeValue(forKey: stored.id) ?? insertedTab(id: stored.id)
            record.url = stored.url
            record.title = stored.title
            record.pinnedURL = stored.pinnedURL
            record.pinnedTitle = stored.pinnedTitle
            record.lastActivity = stored.lastActivity
            record.interactionState = stored.interactionState
            record.place = position.place
            record.order = position.order
            record.folder = position.folderID.flatMap { folders[$0] }
            // Un favori appartient au profil, les autres onglets au Space.
            record.profile = position.place == .favorite ? space.profile : nil
            record.space = position.place == .favorite ? nil : space
        }
        for leftover in existing.values where leftover.place != nil {
            context.delete(leftover)
        }
        do {
            try context.save()
        } catch {
            Logger.app.error("Enregistrement du Space impossible : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Met à jour les dossiers du Space et renvoie les enregistrements par identifiant.
    private func saveFolders(_ entries: [FolderEntry]) -> [UUID: FolderRecord] {
        var existing = Dictionary((space.folders ?? []).map { ($0.id, $0) }) { first, _ in first }
        var saved: [UUID: FolderRecord] = [:]
        for entry in entries {
            let record = existing.removeValue(forKey: entry.id) ?? {
                let folder = FolderRecord(id: entry.id, name: entry.name)
                context.insert(folder)
                return folder
            }()
            record.name = entry.name
            record.order = entry.order
            record.isCollapsed = entry.isCollapsed
            record.space = space
            saved[entry.id] = record
        }
        for entry in entries {
            saved[entry.id]?.parent = entry.parentID.flatMap { saved[$0] }
        }
        for leftover in existing.values {
            context.delete(leftover)
        }
        return saved
    }

    /// Onglets du Space et favoris de son profil.
    private func tabRecords() -> [TabRecord] {
        (space.tabs ?? []) + (space.profile?.favorites ?? [])
    }

    private func insertedTab(id: UUID) -> TabRecord {
        let record = TabRecord(id: id)
        context.insert(record)
        return record
    }
}
