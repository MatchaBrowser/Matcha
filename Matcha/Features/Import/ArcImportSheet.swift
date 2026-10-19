import SwiftUI

/// Arc import preview (task 7.1): the Spaces and what they contain, the favorites, what will be left out, the profile
/// that receives Arc's main profile, and the choice of open tabs (off by default). Nothing is imported without
/// “Import”.
struct ArcImportSheet: View {
    let sidebar: ArcSidebar
    let profiles: [ProfileRecord]
    let initialProfileID: UUID?
    let perform: (ArcImportOptions) -> Void

    @State private var profileID: UUID?
    @State private var includesOpenTabs = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import from Arc")
                    .font(.headline)
                    .accessibilityIdentifier("arcImportTitle")
                Text("Each Arc Space becomes a new Space, with its pinned tabs and folders. Nothing you already have is changed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            spaces
            details
            options
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    perform(ArcImportOptions(profileID: profileID ?? initialProfileID, includesOpenTabs: includesOpenTabs))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sidebar.spaces.isEmpty && favoriteCount == 0)
                .accessibilityIdentifier("arcImportButton")
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }

    /// Arc's Spaces, in order.
    private var spaces: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sidebar.spaces.enumerated()), id: \.offset) { _, space in
                    ArcImportSpaceRow(space: space)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .frame(maxHeight: 240)
        .fixedSize(horizontal: false, vertical: true)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("arcImportSpaces")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if favoriteCount > 0 {
                Label("\(favoriteCount) favorites, added to those of their profile", systemImage: "star")
            }
            if sidebar.skippedItems > 0 {
                Label("\(sidebar.skippedItems) items left out: Arc notes and Arc pages", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            if profiles.count > 1 {
                Picker("Profile", selection: Binding(get: { profileID ?? initialProfileID }, set: { profileID = $0 })) {
                    ForEach(profiles) { profile in
                        Text(verbatim: profile.name).tag(Optional(profile.id))
                    }
                }
                .fixedSize()
                .help("Profile that receives the Spaces of Arc’s main profile")
                .accessibilityIdentifier("arcImportProfilePicker")
            }
            if openTabCount > 0 {
                Toggle(isOn: $includesOpenTabs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also import open tabs")
                        Text("\(openTabCount) tabs, added to Today in their Space")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("arcImportOpenTabsToggle")
            }
        }
    }

    /// Favorites, each address only once per profile.
    private var favoriteCount: Int {
        sidebar.favorites.values.reduce(0) { $0 + ArcImporter.withoutDuplicates($1).count }
    }

    private var openTabCount: Int {
        sidebar.spaces.reduce(0) { $0 + ImportNode.tabCount(of: $1.openTabs) }
    }
}
