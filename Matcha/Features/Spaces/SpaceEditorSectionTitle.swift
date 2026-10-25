import SwiftUI

/// Title of a section of a Space's editor.
struct SpaceEditorSectionTitle: View {
    let title: Text

    init(_ title: Text) {
        self.title = title
    }

    var body: some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
