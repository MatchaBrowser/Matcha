import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers
import WebKit

/// État de Réglages > Extensions (tâche 6.4) : extensions installées, extensions Safari trouvées dans les apps,
/// extension en attente de l'accord de l'utilisateur, et ses actions (ajouter, activer, supprimer…).
@MainActor
@Observable
final class ExtensionsSettingsModel {
    /// Une extension installée, telle que la liste l'affiche.
    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String?
        let icon: NSImage?
        /// App de l'extension Safari ; nil pour une extension installée depuis un fichier.
        let appName: String?
        /// Introuvable : app supprimée, dossier effacé.
        let isMissing: Bool
        let isEnabled: Bool
        let hasOptionsPage: Bool
        let allowsPrivateWindows: Bool
        /// Bouton près de l'adresse affiché (tâche 6.5).
        let showsButton: Bool
    }

    let manager: ExtensionManager
    @ObservationIgnored private let installer: ExtensionInstaller
    /// Extensions Safari des apps installées.
    private(set) var appExtensions: [SafariAppExtension] = []
    /// Extension préparée, montrée dans l'écran des permissions.
    var candidate: ExtensionInstallCandidate?
    /// Dernier échec (préparation, installation), dans la langue de l'utilisateur.
    var errorMessage: String?
    private(set) var isWorking = false
    /// Change à chaque action, pour relire ce qui n'est pas suivi (activée, fenêtres privées).
    private(set) var revision = 0

    init(manager: ExtensionManager) {
        self.manager = manager
        installer = ExtensionInstaller(manager: manager)
    }

    /// Extensions installées, par nom.
    var installed: [Installed] {
        _ = revision
        let identifiers = Set(manager.installedIdentifiers).union(manager.installed.keys)
        return identifiers.map(entry(for:)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Vrai si l'extension Safari `appExtension` est déjà installée.
    func isInstalled(_ appExtension: SafariAppExtension) -> Bool {
        _ = revision
        guard let identifier = ExtensionIdentifier.forAppExtension(bundleIdentifier: appExtension.bundleIdentifier) else {
            return false
        }
        return manager.installed[identifier] != nil || manager.store.state(for: identifier)?.appExtensionPath != nil
    }

    // MARK: Ajouter

    /// Relit les extensions Safari des apps (hors du fil principal : lecture de `/Applications`).
    func refreshAppExtensions() async {
        appExtensions = await Task.detached { SafariExtensionFinder.find() }.value
    }

    /// Choisir un fichier (`.crx`, `.xpi`, `.zip`) ou un dossier décompressé, puis le préparer.
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip]
            + ["crx", "xpi"].compactMap { UTType(filenameExtension: $0, conformingTo: .data) }
        panel.prompt = String(localized: "Choose", comment: "Button of the panel that picks an extension file or folder")
        panel.message = String(localized: "Choose a .crx, .xpi or .zip file, or an unpacked extension folder.")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in await self?.prepare { try await $0.prepare(fileAt: url) } }
        }
    }

    /// Prépare l'extension Safari `appExtension`.
    func add(_ appExtension: SafariAppExtension) {
        Task { await prepare { try await $0.prepare(appExtension) } }
    }

    /// Installe `candidate`, accepté dans l'écran des permissions (passé tel quel : fermer l'écran remet `candidate` à
    /// nil avant que l'installation commence).
    func confirm(_ candidate: ExtensionInstallCandidate, allowsPrivateWindows: Bool) async {
        if self.candidate?.id == candidate.id {
            self.candidate = nil
        }
        isWorking = true
        defer {
            isWorking = false
            revision += 1
        }
        do {
            try await installer.install(candidate, allowsPrivateWindows: allowsPrivateWindows)
        } catch {
            installer.discard(candidate)
            Logger.extensions.error("Extension non installée : \(error.localizedDescription, privacy: .public)")
            errorMessage = ExtensionInstallError(error).localizedDescription
        }
    }

    /// Refus dans l'écran des permissions : rien n'est installé.
    func cancel(_ candidate: ExtensionInstallCandidate) {
        installer.discard(candidate)
        if self.candidate?.id == candidate.id {
            self.candidate = nil
        }
    }

    private func prepare(_ make: (ExtensionInstaller) async throws -> ExtensionInstallCandidate) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            candidate = try await make(installer)
        } catch {
            Logger.extensions.error("Extension non préparée : \(error.localizedDescription, privacy: .public)")
            errorMessage = ExtensionInstallError(error).localizedDescription
        }
    }

    // MARK: Extensions installées

    func setEnabled(_ isEnabled: Bool, for identifier: String) {
        Task {
            do {
                try await manager.setEnabled(isEnabled, identifier: identifier)
            } catch {
                errorMessage = ExtensionInstallError(error).localizedDescription
            }
            revision += 1
        }
    }

    func setAllowsPrivateWindows(_ isAllowed: Bool, for identifier: String) {
        manager.setAccessToPrivateData(isAllowed, identifier: identifier)
        revision += 1
    }

    func setShowsButton(_ shows: Bool, for identifier: String) {
        manager.setShowsButton(shows, identifier: identifier)
        revision += 1
    }

    func openOptions(of identifier: String) {
        manager.openOptionsPage(identifier: identifier)
    }

    func remove(_ identifier: String) {
        Task {
            await manager.uninstall(identifier: identifier)
            revision += 1
        }
    }

    private func entry(for identifier: String) -> Installed {
        let webExtension = manager.installed[identifier]
        let state = manager.store.state(for: identifier)
        return Installed(
            id: identifier,
            name: webExtension?.displayName ?? identifier,
            version: webExtension?.displayVersion ?? webExtension?.version,
            icon: webExtension?.icon(for: CGSize(width: 32, height: 32)),
            appName: state?.appExtensionPath.flatMap(Self.appName(containing:)),
            isMissing: webExtension == nil,
            isEnabled: manager.isEnabled(identifier),
            hasOptionsPage: manager.contexts[identifier]?.optionsPageURL != nil,
            allowsPrivateWindows: state?.hasAccessToPrivateData ?? false,
            showsButton: manager.showsButton(identifier),
        )
    }

    /// Nom de l'app qui contient le `.appex` de `path`.
    private static func appName(containing path: String) -> String? {
        var url = URL(filePath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" {
                return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
