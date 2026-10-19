import SwiftUI

/// Confirmation before deleting a Space that has tabs (audit H2): its pinned and Today tabs close with it, for good;
/// its favorites stay with the profile. A Space without tabs is deleted right away.
struct SpaceDeletionAlert: ViewModifier {
    let model: WindowModel
    @Binding var space: SpaceSession?

    /// Tabs that would close: the Space's own, not the favorites it shows.
    static func closingTabCount(of space: SpaceSession) -> Int {
        space.tabManager.tabs.count - space.tabManager.favoriteTabs.count
    }

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Delete “\(space?.record.name ?? "")”?", comment: "Alert title before deleting a Space; %@ is its name"),
                isPresented: Binding { space != nil } set: {
                    if !$0 {
                        space = nil
                    }
                },
                presenting: space,
            ) { space in
                Button("Delete Space", role: .destructive) {
                    withMotion(.easeInOut(duration: 0.3)) { model.deleteSpace(space) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { space in
                Text(
                    "The \(Self.closingTabCount(of: space)) tabs of this Space will close. You can't undo this action.",
                    comment: "Alert before deleting a Space; the number of pinned and Today tabs",
                )
            }
    }
}
