import AppKit
import SwiftUI

/// Avatar of the sync account in a circle (task 7.9): its image (a photo, or an emoji or initials drawn as an image);
/// without one, the generic person symbol.
struct AccountAvatarView: View {
    /// Decoded once by sync (`SyncService.avatarImage`), never in `body`.
    let image: CGImage?
    var size: Double = 22

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
