import SwiftUI

/// Button of a row of `PrivacySiteList`: a trash can that forgets the row.
struct PrivacySiteRemoveButton: View {
    let title: Text
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { title } icon: { Image(systemName: "trash") }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityIdentifier(identifier)
    }
}
