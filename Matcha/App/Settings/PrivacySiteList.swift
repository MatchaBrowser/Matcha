import SwiftUI

/// A list of websites in Settings > Privacy (permissions, actions allowed without asking, blocker exceptions; review
/// CO4): `empty` without rows; otherwise rows of the same height, which scroll beyond a few (the settings window takes
/// the height of its content).
struct PrivacySiteList<Items: RandomAccessCollection, ID: Hashable, Row: View>: View {
    let items: Items
    let id: KeyPath<Items.Element, ID>
    let empty: Text
    @ViewBuilder let row: (Items.Element) -> Row

    var body: some View {
        if items.isEmpty {
            empty.foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items, id: id) { item in
                        row(item).frame(height: PrivacySiteListLayout.rowHeight)
                    }
                }
            }
            .scrollDisabled(false)
            .frame(height: min(Double(items.count) * PrivacySiteListLayout.rowHeight, PrivacySiteListLayout.maximumHeight))
        }
    }
}

extension PrivacySiteList where Items.Element: Identifiable, ID == Items.Element.ID {
    init(items: Items, empty: Text, @ViewBuilder row: @escaping (Items.Element) -> Row) {
        self.init(items: items, id: \.id, empty: empty, row: row)
    }
}

/// Sizes of `PrivacySiteList`.
private enum PrivacySiteListLayout {
    static let rowHeight = 30.0
    static let maximumHeight = 210.0
}
