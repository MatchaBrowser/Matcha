import SwiftUI

/// Ligne de l'historique : icône du site (celle en cache, sinon l'initiale), titre, domaine et heure de la dernière
/// visite du jour.
struct HistoryRowView: View {
    let row: HistoryRow
    let faviconService: FaviconService

    var body: some View {
        HStack(spacing: 8) {
            CachedSiteIcon(host: row.url.host(), service: faviconService)
                .frame(width: 16, height: 16)
            Text(verbatim: row.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Text(verbatim: row.host)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(row.lastVisit, format: .dateTime.hour().minute())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .help(Text(verbatim: row.url.absoluteString))
        // Texte statique : sous macOS, un simple groupe n'expose pas sa valeur (le domaine).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityValue(Text(verbatim: row.host))
        .accessibilityIdentifier("historyRow")
    }
}
