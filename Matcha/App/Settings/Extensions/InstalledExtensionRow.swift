import SwiftUI

/// Row of an installed extension (task 6.4): icon, name, version and origin, menu (options, button next to the
/// address, private windows, remove) and switch. An extension that cannot be found (app deleted) only has
/// “Remove…”.
struct InstalledExtensionRow: View {
    let item: ExtensionsSettingsModel.Installed
    let model: ExtensionsSettingsModel
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(item.isMissing ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 8)
            Menu {
                if item.hasOptionsPage {
                    Button("Options…") { model.openOptions(of: item.id) }
                }
                if !item.isMissing {
                    Toggle("Show Button Next to the Address", isOn: Binding {
                        item.showsButton
                    } set: {
                        model.setShowsButton($0, for: item.id)
                    })
                    Toggle("Allow in Private Windows", isOn: Binding {
                        item.allowsPrivateWindows
                    } set: {
                        model.setAllowsPrivateWindows($0, for: item.id)
                    })
                    siteAccess
                    Divider()
                }
                Button("Remove…", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Actions")
            .accessibilityLabel(Text("More Actions"))
            .accessibilityIdentifier("installedExtensionMenu")
            Toggle("Enabled", isOn: Binding { item.isEnabled } set: { model.setEnabled($0, for: item.id) })
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(item.isMissing)
                .accessibilityIdentifier("installedExtensionToggle")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("installedExtensionRow")
    }

    /// Websites the extension was given, each one can be taken back (audit E5).
    private var siteAccess: some View {
        Menu {
            if item.grantedSites.isEmpty {
                Text("No Website", comment: "Extension menu: the extension has access to no website")
            }
            ForEach(item.grantedSites, id: \.self) { pattern in
                Button {
                    model.revokeSite(pattern, for: item.id)
                } label: {
                    if let site = ExtensionPromptPolicy.siteName(of: pattern) {
                        Text("Remove Access to \(site)", comment: "Extension menu: takes back the access to a website; %@ is the website")
                    } else {
                        Text("Remove Access to All Websites", comment: "Extension menu: takes back the access to every website")
                    }
                }
            }
        } label: {
            Text("Website Access", comment: "Extension menu: websites the extension can read and change")
        }
    }

    @ViewBuilder private var icon: some View {
        if let image = item.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 18))
                .frame(width: 28, height: 28)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// “Version 1.2 · In Proton Pass for Safari”, “Version 1.2 · From a file”, or “Not found”.
    private var caption: String {
        if item.isMissing {
            return String(localized: "Not found. Its app may have been deleted.", comment: "Installed extension whose files are missing")
        }
        let origin = item.appName.map {
            String(localized: "In \($0)", comment: "App that contains a Safari extension, e.g. In Proton Pass for Safari")
        } ?? String(localized: "From a file", comment: "Origin of an extension installed from a .crx, .xpi or .zip file or a folder")
        guard let version = item.version else {
            return origin
        }
        return String(localized: "Version \(version) · \(origin)", comment: "Version and origin of an installed extension")
    }
}
