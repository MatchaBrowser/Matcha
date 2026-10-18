import SwiftUI

/// « Depuis vos autres Mac » (tâche 7.4) : les extensions installées sur vos autres Mac et pas sur celui-ci, ou dont la
/// mise à jour demande votre accord. « Ajouter… » passe par l'écran des permissions ; « Ignorer » la retire de la liste
/// sur ce Mac seulement. Absente tant qu'il n'y a rien à proposer.
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

/// Une extension proposée : nom, origine et version, puis « Ajouter… » (ou « Mettre à jour… »), « Obtenir l'app »
/// quand son app manque, et « Ignorer ».
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
            Button("Ignore") { model.ignoreOffer(offer) }
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
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("syncedExtensionRow")
    }

    /// « Dans Proton Pass » ou « Version 4.9 · darkreader.xpi ».
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
