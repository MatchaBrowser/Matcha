import SwiftUI

/// Preview displayed under the pointer during a drag.
struct SidebarDragPreview<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 8) {
            icon()
            Text(title)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
    }
}
