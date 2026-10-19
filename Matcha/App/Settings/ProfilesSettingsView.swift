import SwiftUI

/// Profile settings: each one has its own cookies, logins and favorites, shared by its Spaces.
struct ProfilesSettingsView: View {
    @Environment(BrowserSession.self) private var session
    @Environment(MiniWindowManager.self) private var miniWindows: MiniWindowManager?
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
        // The window takes the height of its content: no scroll bar.
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
                    // Its mini windows close first: their pages no longer use its data.
                    miniWindows?.closeWindows(ofProfile: profile.id)
                    Task { await session.deleteProfile(profile) }
                }
            }
        } message: {
            Text("Its Spaces, tabs, Favorites, cookies, and sign-ins will be deleted.")
        }
    }
}

/// Row of a profile: editable name, number of Spaces, deletion.
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
