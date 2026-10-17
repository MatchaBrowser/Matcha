import SwiftUI

/// Pied de la barre latérale : une icône par Space et le bouton pour en créer un. Un clic affiche le
/// Space ; sur le Space affiché, il ouvre l'éditeur de son thème. Menu contextuel : renommer, thème,
/// icône, supprimer.
struct SpaceSwitcher: View {
    let model: WindowModel

    @State private var editedTheme: SpaceSession?
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
                editedTheme = space
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { model.select(space) }
            }
        } label: {
            Image(systemName: space.record.symbol)
                .font(.system(size: isCurrent ? 11 : 9))
                .foregroundStyle(isCurrent ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(isCurrent ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.session.profiles.count > 1 ? "\(space.record.name) — \(space.record.profile?.name ?? "")" : space.record.name)
        .accessibilityLabel("Space \(space.record.name)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier("spaceButton")
        .contextMenu { menu(for: space) }
        .popover(isPresented: Binding { editedTheme === space } set: {
            if !$0 {
                editedTheme = nil
            }
        }, arrowEdge: .top) {
            SpaceThemeEditor(theme: Binding { space.theme } set: { space.setTheme($0) })
        }
    }

    @ViewBuilder private func menu(for space: SpaceSession) -> some View {
        Button("Rename…") {
            newName = space.record.name
            renamedSpace = space
        }
        Button("Edit Theme…") {
            model.select(space)
            editedTheme = space
        }
        Menu("Icon") {
            ForEach(BrowserSession.spaceSymbols, id: \.self) { symbol in
                Button {
                    model.session.setSymbol(symbol, of: space)
                } label: {
                    Label(symbol, systemImage: symbol)
                }
            }
        }
        Divider()
        Button("Delete Space") {
            withAnimation(.easeInOut(duration: 0.3)) { model.deleteSpace(space) }
        }
        .disabled(model.session.spaces.count <= 1)
    }
}
