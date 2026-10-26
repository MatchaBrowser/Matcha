import SwiftUI

/// “From Your Other Macs” (`SYNC.md` § 2.5): the extensions installed on your other Macs and not on this one, and the
/// updates of installed ones, never installed without a click here. “Add…” or “Update…” goes through the permissions
/// screen; “Ignore” removes it from the list on this Mac only, “Ignore This Version” keeps the installed version
/// until a later one. Absent as long as there is nothing to offer.
struct SyncedExtensionsSection: View {
    let model: ExtensionsSettingsModel

    var body: some View {
        let offers = model.offers
        if !offers.isEmpty {
            Section {
                ForEach(offers, id: \.identifier) { offer in
                    SyncedExtensionRow(offer: offer, model: model)
                }
            } header: {
                Text("From Your Other Macs")
            } footer: {
                Text("Installed on your other Macs. Nothing is added to this Mac without your consent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// An offered extension: name, origin and version, then “Add…” (or “Update…”), “Get the App” when its app is
/// missing, and “Ignore”.
private struct SyncedExtensionRow: View {
    let offer: SyncExtensionFields
    let model: ExtensionsSettingsModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: offer.name)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(model.isUpdate(offer) ? "Ignore This Version" : "Ignore") { model.ignoreOffer(offer) }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("syncedExtensionIgnoreButton")
            switch model.availability(of: offer) {
            case .ready:
                Button(model.isUpdate(offer) ? "Update…" : "Add…") { model.addOffer(offer) }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("syncedExtensionAddButton")
            case .appMissing:
                Button("Get the App") { model.openAppStore(for: offer) }
                    .help("The app that contains this Safari extension isn't on this Mac")
            case .packageUnavailable:
                Text("Unavailable", comment: "An extension from another Mac whose package can't be downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Its package isn't available. Install it from its file.")
            case .packageLost:
                Text("To Reinstall", comment: "An extension from another Mac whose package was never found on the sync server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Its package wasn't found on the sync server. Install it from its file, or try again.")
                Button("Try Again") { model.addOffer(offer) }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("syncedExtensionRetryButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("syncedExtensionRow")
    }

    /// “In Proton Pass” or “Version 4.9 · darkreader.xpi”.
    private var caption: String {
        let origin = switch offer.source.kind {
        case .appExtension:
            String(
                localized: "In \(offer.source.appName ?? offer.name)",
                comment: "App that contains a Safari extension, e.g. In Proton Pass for Safari",
            )
        case .package:
            offer.source.fileName ?? offer.identifier
        }
        guard let version = offer.version else {
            return origin
        }
        return String(localized: "Version \(version) · \(origin)", comment: "Version and origin of an installed extension")
    }
}
