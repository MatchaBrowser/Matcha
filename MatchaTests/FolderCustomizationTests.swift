import Foundation
@testable import Matcha
import Observation
import Testing
import WebKit

/// Apparence des dossiers par `TabManager`, et panneau de personnalisation d'une fenêtre (`WindowModel`).
@MainActor
struct FolderCustomizationTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    /// Marque posée par le framework Observation quand le rangement change.
    private final class ChangeFlag: @unchecked Sendable {
        var isSet = false
    }

    @Test func `new folders have the default appearance`() {
        let folder = manager.newFolder()
        #expect(manager.layout.pinned.folder(folder)?.appearance == .default)
    }

    @Test func `appearance is set as it will be saved`() {
        let folder = manager.newFolder()
        let picked = ThemeColor(red: 0.123_456, green: 0.5, blue: 0.987_654)
        manager.setFolderAppearance(folder, FolderAppearance(icon: .symbol("star"), textColor: picked))
        let appearance = manager.layout.pinned.folder(folder)?.appearance
        #expect(appearance?.icon == .symbol("star"))
        #expect(appearance?.textColor == ThemeColor(hexString: "#1F80FC"))
        #expect(appearance?.backgroundColor == nil)

        // Un emoji invalide donne l'icône par défaut.
        manager.setFolderAppearance(folder, FolderAppearance(icon: .emoji("ab")))
        #expect(manager.layout.pinned.folder(folder)?.appearance == .default)
    }

    @Test func `update changes only what it touches, in nested folders too`() {
        let parent = manager.newFolder()
        let child = manager.newFolder(in: parent)
        let green = ThemeColor(rgb: 0x34C759)
        manager.updateFolderAppearance(child) { $0.icon = .emoji("🌿") }
        manager.updateFolderAppearance(child) { $0.backgroundColor = green }
        #expect(manager.layout.pinned.folder(child)?.appearance == FolderAppearance(icon: .emoji("🌿"), backgroundColor: green))
        #expect(manager.layout.pinned.folder(parent)?.appearance == .default)

        // « Réinitialiser ».
        manager.setFolderAppearance(child, .default)
        #expect(manager.layout.pinned.folder(child)?.appearance == .default)
    }

    @Test func `an unknown folder or an unchanged appearance leaves the layout untouched`() {
        let folder = manager.newFolder()
        manager.setFolderAppearance(folder, FolderAppearance(icon: .symbol("leaf")))
        let flag = ChangeFlag()
        withObservationTracking {
            _ = manager.layout
        } onChange: {
            flag.isSet = true
        }
        manager.setFolderAppearance(folder, FolderAppearance(icon: .symbol("leaf")))
        manager.setFolderAppearance(UUID(), FolderAppearance(icon: .symbol("star")))
        manager.updateFolderAppearance(UUID()) { $0.icon = .symbol("star") }
        #expect(!flag.isSet)
        manager.updateFolderAppearance(folder) { $0.icon = .symbol("star") }
        #expect(flag.isSet)
    }

    @Test func `the appearance follows the folder when it moves`() {
        let first = manager.newFolder()
        let second = manager.newFolder()
        manager.setFolderAppearance(first, FolderAppearance(icon: .symbol("flame")))
        manager.moveFolder(first, to: .pinned(folder: second, index: 0))
        #expect(manager.layout.pinned.folder(first)?.appearance.icon == .symbol("flame"))
        // Supprimer le parent garde le sous-dossier et son apparence.
        manager.deleteFolder(second)
        #expect(manager.layout.pinned.folder(first)?.appearance.icon == .symbol("flame"))
    }

    @Test func `one customization panel per window`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let model = WindowModel(session: session, defaults: nil)
        let first = UUID()
        let second = UUID()
        #expect(model.customizedFolderID == nil)
        model.toggleFolderCustomization(first)
        #expect(model.customizedFolderID == first)
        // Ouvrir celui d'un autre dossier déplace le panneau.
        model.toggleFolderCustomization(second)
        #expect(model.customizedFolderID == second)
        // Le même élément du menu le ferme.
        model.toggleFolderCustomization(second)
        #expect(model.customizedFolderID == nil)
    }
}
