import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Sync, avatar of the account (task 7.9, `SYNC.md` § 4.4): a photo, an emoji or initials on a color, made
/// into an image on this Mac, encrypted, and kept by the server for the account's other Macs. Shown in the circle at
/// the bottom of the sidebar. Only with a server that keeps avatars. An emoji or a color applies at once.
struct SyncAvatarSection: View {
    /// Colors offered for initials.
    static let colors = ["#0A84FF", "#30B0C7", "#34C759", "#FF9F0A", "#FF453A", "#BF5AF2", "#8E8E93"]
    /// Emoji offered in one click; “Other…” opens the Character Viewer.
    static let emojis = ["🍵", "🌿", "🦊", "🐱", "🐼", "🚀", "⭐️", "🎧"]

    let sync: SyncService

    @State private var emoji: String?
    @State private var choosesOtherEmoji = false
    @State private var initials = ""
    @State private var color = colors[0]
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            HStack(spacing: 14) {
                AccountAvatarView(image: sync.avatarImage, size: 48)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Choose Photo…", action: choosePhoto)
                if sync.avatar != nil {
                    Button("Remove") { save(nil) }
                }
            }
            LabeledContent("Emoji") {
                HStack(spacing: 2) {
                    ForEach(Self.emojis, id: \.self) { candidate in
                        Button {
                            chooseEmoji(candidate)
                        } label: {
                            Text(verbatim: candidate)
                                .font(.system(size: 17))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(emoji == candidate ? 0.15 : 0)),
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: candidate))
                    }
                    Button("Other…") { choosesOtherEmoji = true }
                        .padding(.leading, 6)
                        .popover(isPresented: $choosesOtherEmoji, arrowEdge: .bottom) {
                            IconEmojiField(
                                emoji: emoji,
                                identifierPrefix: "avatarEmoji",
                                close: { choosesOtherEmoji = false },
                                choose: chooseOtherEmoji,
                            )
                            .padding(12)
                            .frame(width: 240)
                        }
                }
            }
            LabeledContent("Initials") {
                HStack(spacing: 8) {
                    TextField("Initials", text: $initials, prompt: Text(verbatim: suggestedInitials))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .onSubmit(useInitials)
                    ForEach(Self.colors, id: \.self) { swatch in
                        Button {
                            color = swatch
                            useInitials()
                        } label: {
                            Circle()
                                .fill(AvatarImage.color(swatch))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.primary.opacity(color == swatch ? 0.6 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help("Use the initials on this color")
                        .accessibilityLabel(Text("Color \(swatch)"))
                    }
                }
            }
        } header: {
            Text("Avatar")
        } footer: {
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Shown at the bottom of the sidebar, on all your synced Macs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isWorking)
    }

    /// Initials taken from the account's email: “jeremy.mouton@…” gives “JM”, “jeremy@…” gives “J”.
    private var suggestedInitials: String {
        AvatarImage.initials(fromEmail: sync.configuration.email ?? "")
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        guard let data = AvatarImage.photo(from: url, maximumBytes: sync.maximumAvatarBytes) else {
            errorMessage = String(localized: "This image can't be used as an avatar.")
            return
        }
        save(data)
    }

    /// An emoji typed or chosen in the Character Viewer: applied, and the popover closes.
    private func chooseOtherEmoji(_ chosen: String?) {
        chooseEmoji(chosen)
        if chosen != nil {
            choosesOtherEmoji = false
        }
    }

    /// An emoji typed or chosen in the Character Viewer; emptying the field changes nothing.
    private func chooseEmoji(_ chosen: String?) {
        guard let chosen, let data = AvatarImage.emoji(chosen) else {
            return
        }
        emoji = chosen
        save(data)
    }

    private func useInitials() {
        let letters = AvatarImage.initials(from: initials.isEmpty ? suggestedInitials : initials)
        guard !letters.isEmpty, let data = AvatarImage.initials(letters, color: color) else {
            return
        }
        initials = letters
        emoji = nil
        save(data)
    }

    private func save(_ image: Data?) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await sync.setAvatar(image)
            } catch {
                errorMessage = SyncErrorText.message(for: error)
            }
            isWorking = false
        }
    }
}
