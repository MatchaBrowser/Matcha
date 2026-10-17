import SwiftUI

/// Réglages des profils : chacun a ses cookies, ses connexions et ses favoris, partagés par ses Spaces.
struct ProfilesSettingsView: View {
    @Environment(BrowserSession.self) private var session
    @State private var profileToDelete: ProfileRecord?

    var body: some View {
        Form {
            Section {
                ForEach(session.profiles, id: \.id) { profile in
                    ProfileRow(profile: profile, session: session) { profileToDelete = profile }
                }
            } footer: {
                Text("Each profile has its own cookies, sign-ins, and Favorites, shared by its Spaces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("New Profile") { session.addProfile(named: "") }
                .accessibilityIdentifier("newProfileButton")
        }
        .formStyle(.grouped)
        // La fenêtre prend la hauteur du contenu : pas de barre de défilement.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Delete the profile “\(profileToDelete?.name ?? "")”?",
            isPresented: Binding { profileToDelete != nil } set: {
                if !$0 {
                    profileToDelete = nil
                }
            },
        ) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    Task { await session.deleteProfile(profile) }
                }
            }
        } message: {
            Text("Its Spaces, tabs, Favorites, cookies, and sign-ins will be deleted.")
        }
    }
}

/// Ligne d'un profil : nom modifiable, nombre de Spaces, suppression.
private struct ProfileRow: View {
    let profile: ProfileRecord
    let session: BrowserSession
    let delete: () -> Void

    @State private var name = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        let spaceCount = session.spaces(of: profile).count
        HStack {
            TextField("Profile name", text: $name)
                .labelsHidden()
                .focused($isEditing)
                .onSubmit { session.renameProfile(profile, to: name) }
                .onChange(of: isEditing) { _, editing in
                    if !editing {
                        session.renameProfile(profile, to: name)
                    }
                }
                .accessibilityIdentifier("profileNameField")
            Text("\(spaceCount) Spaces")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete Profile", systemImage: "trash", action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(session.profiles.count <= 1)
        }
        .onAppear { name = profile.name }
    }
}
