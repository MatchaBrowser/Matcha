import SwiftUI

/// Pied de la barre latérale : une icône par Space et le bouton pour en créer un. Un clic affiche le
/// Space ; sur le Space affiché, il ouvre son éditeur (icône et thème). Menu contextuel : renommer,
/// thème, icône, supprimer.
struct SpaceSwitcher: View {
    let model: WindowModel

    @State private var editedSpace: SpaceSession?
    @State private var renamedSpace: SpaceSession?
    @State private var newName = ""

    var body: some View {
        if model.session.isPrivate {
            privateBadge
        } else {
            switcher
        }
    }

    /// Fenêtre privée : pas de Spaces, un rappel qu'on navigue en privé.
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
    }

    private func spaceButton(_ space: SpaceSession) -> some View {
        let isCurrent = space === model.space
        return Button {
            if isCurrent {
                editedSpace = space
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
        .popover(isPresented: Binding { editedSpace === space } set: {
            if !$0 {
                editedSpace = nil
            }
        }, arrowEdge: .top) {
            SpaceEditor(space: space) { editedSpace = nil }
        }
    }

    /// Symbole gris (plus grand et au premier plan pour le Space affiché), ou emoji, qui garde ses couleurs et
    /// s'atténue pour un autre Space.
    private func icon(of space: SpaceSession, isCurrent: Bool) -> some View {
        SidebarIconView(
            icon: space.icon,
            defaultSymbol: SidebarIcon.defaultSpaceSymbol,
            tint: isCurrent ? .primary : .secondary,
            size: isCurrent ? 11 : 9,
            emojiSize: isCurrent ? 14 : 12,
        )
        .opacity(isCurrent || space.icon.emoji == nil ? 1 : 0.6)
    }

    /// En Debug, l'icône sous sa forme enregistrée (« symbol:star.fill », « emoji:🌿 »), pour les tests d'interface.
    private func iconSummary(of space: SpaceSession) -> Text {
        #if DEBUG
            return Text(verbatim: space.icon.storedValue ?? "")
        #else
            return Text(verbatim: "")
        #endif
    }

    /// Affiche le Space et ouvre son éditeur.
    private func edit(_ space: SpaceSession) {
        model.select(space)
        editedSpace = space
    }

    @ViewBuilder private func menu(for space: SpaceSession) -> some View {
        Button("Rename…") {
            newName = space.record.name
            renamedSpace = space
        }
        Button("Edit Theme…") { edit(space) }
        Button("Change Icon…") { edit(space) }
        Divider()
        Button("Delete Space") {
            withAnimation(.easeInOut(duration: 0.3)) { model.deleteSpace(space) }
        }
        .disabled(model.session.spaces.count <= 1)
    }
}
