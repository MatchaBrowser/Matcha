import SwiftUI

/// Settings > Extensions (task 6.4): the installed extensions (enable, options, private windows, remove), then
/// “Add”: the Safari extensions of the installed apps (and the App Store, “More Extensions…”), and a file (Chrome
/// `.crx`, Firefox `.xpi`, `.zip`) or an unpacked folder (and the link to Firefox add-ons). Each addition goes
/// through the permissions screen.
struct ExtensionsSettingsView: View {
    @State private var model = ExtensionsSettingsModel(manager: .shared, syncAdapter: .shared)
    @State private var pendingRemoval: ExtensionsSettingsModel.Installed?

    var body: some View {
        Form {
            Section("Installed Extensions") {
                let installed = model.installed
                if installed.isEmpty {
                    Text("No extensions installed.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("extensionsEmptyState")
                }
                ForEach(installed) { item in
                    InstalledExtensionRow(item: item, model: model) { pendingRemoval = item }
                }
            }
            SyncedExtensionsSection(model: model)
            Section {
                ForEach(model.appExtensions) { appExtension in
                    SafariExtensionRow(appExtension: appExtension, isInstalled: model.isInstalled(appExtension)) {
                        model.add(appExtension)
                    }
                }
                if model.appExtensions.isEmpty {
                    Text("No Safari extensions were found in your apps. They are installed from the App Store.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("More Extensions…") { model.openAppStore() }
                    .help("Open the Safari Extensions page of the App Store")
                    .accessibilityIdentifier("extensionsAppStoreButton")
            } header: {
                Text("Safari Extensions from Your Apps")
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From a File")
                        Text("A .crx file (Chrome), an .xpi file (Firefox), a .zip file, or an unpacked folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Choose…") { model.chooseFile() }
                        .disabled(model.isWorking)
                        .accessibilityIdentifier("extensionsChooseFileButton")
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Firefox extensions work too: get the .xpi file from the extension's versions page on addons.mozilla.org.")
                        Text("When an extension also exists for Safari, prefer the Safari version.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Firefox Add-ons") { model.openFirefoxAddOns() }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("Open addons.mozilla.org in a new tab")
                        .accessibilityIdentifier("extensionsFirefoxAddOnsButton")
                }
                if let message = model.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("extensionsErrorMessage")
                }
            } footer: {
                Text("Extensions can read and change the pages they have access to. Add only extensions you trust.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // The window takes the height of its content: no scroll bar.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.refreshAppExtensions() }
        .sheet(item: $model.candidate) { candidate in
            ExtensionReviewSheet(candidate: candidate) { allowsPrivateWindows in
                Task { await model.confirm(candidate, allowsPrivateWindows: allowsPrivateWindows) }
            } cancel: {
                model.cancel(candidate)
            }
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding { pendingRemoval != nil } set: {
                if !$0 {
                    pendingRemoval = nil
                }
            },
        ) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval {
                    model.remove(pendingRemoval.id)
                }
            }
        } message: {
            Text("Its settings and data will be deleted. A Safari extension stays in its app.")
        }
    }
}

/// Safari extension of an app: app icon, name, app, and “Add…” (or “Installed”).
private struct SafariExtensionRow: View {
    let appExtension: SafariAppExtension
    let isInstalled: Bool
    let add: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appExtension.appURL.path))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: appExtension.displayName)
                Text("In \(appExtension.appName)", comment: "App that contains a Safari extension, e.g. In Proton Pass for Safari")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isInstalled {
                Text("Installed", comment: "A Safari extension that is already installed in Matcha")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add…", action: add)
                    .accessibilityIdentifier("extensionsAddSafariExtensionButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("safariExtensionRow")
    }
}
