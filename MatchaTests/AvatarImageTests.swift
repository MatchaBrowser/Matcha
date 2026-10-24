import AppKit
@testable import Matcha
import Testing

/// Images of the account's avatar (task 7.9): an emoji or initials drawn on this Mac.
@MainActor
struct AvatarImageTests {
    @Test func `an emoji and initials become square images`() throws {
        for data in [AvatarImage.emoji("🍵"), AvatarImage.initials("JM", color: "#34C759")] {
            let image = try #require(data.flatMap(NSImage.init(data:)))
            #expect(image.representations.first?.pixelsWide == AvatarImage.side)
        }
        #expect(AvatarImage.initials(fromEmail: "jeremy.mouton@example.com") == "JM")
        #expect(AvatarImage.initials(fromEmail: "moutonjeremy@labbs.fr") == "M")
    }
}
