import SwiftUI

/// Ligne d'une extension installée (tâche 6.4) : icône, nom, version et origine, menu (options, fenêtres privées,
/// supprimer) et interrupteur. Une extension introuvable (app supprimée) n'a que « Supprimer ».
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
                    Toggle("Allow in Private Windows", isOn: Binding {
                        item.allowsPrivateWindows
                    } set: {
                        model.setAllowsPrivateWindows($0, for: item.id)
                    })
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

    /// « Version 1.2 · Dans Proton Pass for Safari », « Version 1.2 · Depuis un fichier », ou « Introuvable ».
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
