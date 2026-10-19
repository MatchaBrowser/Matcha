import SwiftUI

/// Footer of the sidebar: one icon per Space and the button to create one. A click displays the
/// Space; on the displayed Space, it opens its editor (icon and theme). Context menu: rename,
/// theme, icon, delete.
struct SpaceSwitcher: View {
    let model: WindowModel

    @State private var renamedSpace: SpaceSession?
    @State private var deletedSpace: SpaceSession?
    @State private var newName = ""

    var body: some View {
        if model.session.isPrivate {
            privateBadge
        } else {
            switcher
        }
    }

    /// Private window: no Spaces, a reminder that browsing is private.
    private var privateBadge: some View {
        Label("Private Browsing", systemImage: "eyeglasses")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .accessibilityIdentifier("privateBadge")
    }

    private var switcher: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(model.session.spaces) { space in
                spaceButton(space)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) {
            Button("New Space", systemImage: "plus") {
                withAnimation(.easeInOut(duration: 0.3)) { model.newSpace() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .help("New Space")
            .accessibilityIdentifier("newSpaceButton")
        }
        .frame(height: 28)
        .alert("Rename Space", isPresented: Binding { renamedSpace != nil } set: {
            if !$0 {
                renamedSpace = nil
            }
        }) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renamedSpace {
                    model.session.renameSpace(renamedSpace, to: newName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(SpaceDeletionAlert(model: model, space: $deletedSpace))
    }

    private func spaceButton(_ space: SpaceSession) -> some View {
        let isCurrent = space === model.space
        return Button {
            if isCurrent {
                model.editedSpaceID = space.id
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { model.select(space) }
            }
        } label: {
            icon(of: space, isCurrent: isCurrent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(isCurrent ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.session.profiles.count > 1 ? "\(space.record.name) — \(space.record.profile?.name ?? "")" : space.record.name)
        .accessibilityLabel("Space \(space.record.name)")
        .accessibilityValue(iconSummary(of: space))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("spaceButton")
        .contextMenu { menu(for: space) }
        .popover(isPresented: Binding { model.editedSpaceID == space.id } set: {
            if !$0, model.editedSpaceID == space.id {
                model.editedSpaceID = nil
            }
        }, arrowEdge: .top) {
            SpaceEditor(space: space) { model.editedSpaceID = nil }
        }
    }

    /// Gray symbol (larger and in the foreground for the displayed Space), or emoji, which keeps its colors and is
    /// dimmed for another Space. A single `Text` (`SidebarIconView.text`): the editor's popover stays in the
    /// accessibility tree when an emoji replaces the symbol.
    private func icon(of space: SpaceSession, isCurrent: Bool) -> some View {
        SidebarIconView.text(
            space.icon,
            defaultSymbol: SidebarIcon.defaultSpaceSymbol,
            tint: isCurrent ? .primary : .secondary,
            size: isCurrent ? 11 : 9,
            emojiSize: isCurrent ? 14 : 12,
        )
        .opacity(isCurrent || space.icon.emoji == nil ? 1 : 0.6)
    }

    /// In Debug, the icon in its saved form (“symbol:star.fill”, “emoji:🌿”), for the UI tests.
    private func iconSummary(of space: SpaceSession) -> Text {
        #if DEBUG
            return Text(verbatim: space.icon.storedValue ?? "")
        #else
            return Text(verbatim: "")
        #endif
    }

    @ViewBuilder private func menu(for space: SpaceSession) -> some View {
        Button("Rename…") {
            newName = space.record.name
            renamedSpace = space
        }
        Button("Edit Theme…") { model.editSpace(space) }
        Button("Change Icon…") { model.editSpace(space) }
        Divider()
        Button("Delete Space") {
            if SpaceDeletionAlert.closingTabCount(of: space) > 0 {
                deletedSpace = space
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { model.deleteSpace(space) }
            }
        }
        .disabled(model.session.spaces.count <= 1)
    }
}
