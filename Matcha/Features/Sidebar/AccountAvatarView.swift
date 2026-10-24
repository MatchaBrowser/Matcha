import AppKit
import SwiftUI

/// Avatar of the sync account in a circle (task 7.9): its image (a photo, or an emoji or initials drawn as an image);
/// without one, the generic person symbol.
struct AccountAvatarView: View {
    let image: Data?
    var size: Double = 22

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let image = image.flatMap(NSImage.init(data:)) {
            Image(nsImage: image)
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
