import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers
import WebKit

/// State of Settings > Extensions (task 6.4): installed extensions, Safari extensions found in apps, the extension
/// waiting for the user's approval, and its actions (add, enable, remove…).
@MainActor
@Observable
final class ExtensionsSettingsModel {
    /// An installed extension, as the list shows it.
    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String?
        let icon: NSImage?
        /// App of the Safari extension; nil for an extension installed from a file.
        let appName: String?
        /// Cannot be found: app deleted, folder erased.
        let isMissing: Bool
        let isEnabled: Bool
        let hasOptionsPage: Bool
        let allowsPrivateWindows: Bool
        /// Button next to the address shown (task 6.5).
        let showsButton: Bool
        /// Websites it was given access to (match patterns), which the user can take back (audit E5).
        let grantedSites: [String]
    }

    let manager: ExtensionManager
    /// Extensions offered by your other Macs (task 7.4).
    let syncAdapter: ExtensionSyncAdapter
    @ObservationIgnored private let installer: ExtensionInstaller
    /// Offered extension being added: removed from the offers once installed.
    @ObservationIgnored var installingOffer: SyncExtensionFields?
    /// Safari extensions of the installed apps.
    private(set) var appExtensions: [SafariAppExtension] = []
    /// Prepared extension, shown in the permissions screen.
    var candidate: ExtensionInstallCandidate?
    /// Last failure (preparation, installation), in the user's language.
    var errorMessage: String?
    private(set) var isWorking = false
    /// Icons and app names already read: `installed` and the rows are read at each drawing (review IU8).
    @ObservationIgnored private var icons: [ObjectIdentifier: NSImage] = [:]
    @ObservationIgnored private var appNames: [String: String] = [:]
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]

    init(manager: ExtensionManager, syncAdapter: ExtensionSyncAdapter) {
        self.manager = manager
        self.syncAdapter = syncAdapter
        installer = ExtensionInstaller(manager: manager)
    }

    /// Installed extensions, by name.
    var installed: [Installed] {
        let identifiers = Set(manager.installedIdentifiers).union(manager.installed.keys)
        return identifiers.map(entry(for:)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// True if the Safari extension `appExtension` is already installed: an installed extension comes from its `.appex`
    /// (its identifier may have a suffix, review EX4).
    func isInstalled(_ appExtension: SafariAppExtension) -> Bool {
        let path = appExtension.extensionURL.path
        return manager.installedIdentifiers.contains { manager.store.state(for: $0)?.appExtensionPath == path }
    }

    /// Icon of the app of `appExtension`, read once.
    func appIcon(of appExtension: SafariAppExtension) -> NSImage {
        let path = appExtension.appURL.path
        if let icon = appIcons[path] {
            return icon
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        appIcons[path] = icon
        return icon
    }

    // MARK: Add

    /// Reads the apps' Safari extensions again (off the main thread: reads `/Applications`).
    func refreshAppExtensions() async {
        appExtensions = await SafariExtensionFinder.findInBackground()
    }

    /// Choose a file (`.crx`, `.xpi`, `.zip`) or an unpacked folder, then prepare it.
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

    /// App Store on its Safari extensions page, like Safari's “More Extensions”; without the App Store app, the
    /// same page in a tab.
    func openAppStore() {
        if let url = URL(string: "macappstore://apps.apple.com/story/id1377753262"), NSWorkspace.shared.open(url) {
            return
        }
        if let url = URL(string: "https://apps.apple.com/mac/story/id1377753262") {
            manager.openInBrowser(url)
        }
    }

    /// Firefox add-ons (addons.mozilla.org) in a Matcha tab, otherwise in the default browser.
    func openFirefoxAddOns() {
        guard let url = URL(string: "https://addons.mozilla.org/firefox/") else {
            return
        }
        if !manager.openInBrowser(url) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Prepares the Safari extension `appExtension`.
    func add(_ appExtension: SafariAppExtension) {
        Task { await prepare { try await $0.prepare(appExtension) } }
    }

    /// Installs `candidate`, accepted in the permissions screen (passed as is: closing the screen resets `candidate`
    /// to nil before the installation starts).
    func confirm(_ candidate: ExtensionInstallCandidate, allowsPrivateWindows: Bool) async {
        if self.candidate?.id == candidate.id {
            self.candidate = nil
        }
        isWorking = true
        defer {
            isWorking = false
        }
        do {
            try await installer.install(candidate, allowsPrivateWindows: allowsPrivateWindows)
            if let offer = installingOffer, offer.identifier == candidate.identifier {
                syncAdapter.didInstallOffer(offer)
            }
            installingOffer = nil
        } catch {
            installer.discard(candidate)
            Logger.extensions.error("Extension not installed: \(error.logSummary, privacy: .public)")
            errorMessage = ExtensionInstallError(error).localizedDescription
        }
    }

    /// Declined in the permissions screen: nothing is installed.
    func cancel(_ candidate: ExtensionInstallCandidate) {
        installingOffer = nil
        installer.discard(candidate)
        if self.candidate?.id == candidate.id {
            self.candidate = nil
        }
    }

    func prepare(_ make: (ExtensionInstaller) async throws -> ExtensionInstallCandidate) async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            candidate = try await make(installer)
        } catch {
            Logger.extensions.error("Extension not prepared: \(error.logSummary, privacy: .public)")
            errorMessage = ExtensionInstallError(error).localizedDescription
        }
    }

    // MARK: Installed extensions

    func setEnabled(_ isEnabled: Bool, for identifier: String) {
        Task {
            do {
                try await manager.setEnabled(isEnabled, identifier: identifier)
            } catch {
                errorMessage = ExtensionInstallError(error).localizedDescription
            }
        }
    }

    func setAllowsPrivateWindows(_ isAllowed: Bool, for identifier: String) {
        manager.setAccessToPrivateData(isAllowed, identifier: identifier)
    }

    /// Takes back an extension's access to a website: it may ask again (audit E5).
    func revokeSite(_ pattern: String, for identifier: String) {
        manager.revokeSite(pattern, identifier: identifier)
    }

    func setShowsButton(_ shows: Bool, for identifier: String) {
        manager.toolbar.setShowsButton(shows, identifier: identifier)
    }

    func openOptions(of identifier: String) {
        manager.openOptionsPage(identifier: identifier)
    }

    func remove(_ identifier: String) {
        Task {
            await manager.uninstall(identifier: identifier)
        }
    }

    private func entry(for identifier: String) -> Installed {
        let webExtension = manager.installed[identifier]
        let state = manager.store.state(for: identifier)
        return Installed(
            id: identifier,
            name: webExtension?.displayName ?? identifier,
            version: webExtension?.displayVersion ?? webExtension?.version,
            icon: webExtension.flatMap(icon(of:)),
            appName: state?.appExtensionPath.flatMap(appName(containing:)),
            isMissing: webExtension == nil,
            isEnabled: manager.isEnabled(identifier),
            hasOptionsPage: manager.contexts[identifier]?.optionsPageURL != nil,
            allowsPrivateWindows: state?.hasAccessToPrivateData ?? false,
            showsButton: manager.toolbar.showsButton(identifier),
            // The saved decisions follow the extension's (`saveState`): observed, unlike its context.
            grantedSites: Array((state?.grantedMatchPatterns ?? [:]).keys).sorted(),
        )
    }

    /// Icon of `webExtension`, read once.
    private func icon(of webExtension: WKWebExtension) -> NSImage? {
        let key = ObjectIdentifier(webExtension)
        if let icon = icons[key] {
            return icon
        }
        let icon = webExtension.icon(for: CGSize(width: 32, height: 32))
        icons[key] = icon
        return icon
    }

    /// Name of the app that contains the `.appex` at `path`, read once.
    private func appName(containing path: String) -> String? {
        if let name = appNames[path] {
            return name
        }
        let name = Self.readAppName(containing: path)
        appNames[path] = name
        return name
    }

    private static func readAppName(containing path: String) -> String? {
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
