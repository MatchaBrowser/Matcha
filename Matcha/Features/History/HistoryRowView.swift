import SwiftUI

/// History row: site icon (the cached one, otherwise the initial), title, domain and time of the day's last
/// visit.
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
        // Static text: on macOS, a plain group does not expose its value (the domain).
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(Text(verbatim: row.title))
        // The domain, then the time of the visit (review IU21).
        .accessibilityValue(Text(verbatim: "\(row.host), \(row.lastVisit.formatted(.dateTime.hour().minute()))"))
        .accessibilityIdentifier("historyRow")
    }
}
