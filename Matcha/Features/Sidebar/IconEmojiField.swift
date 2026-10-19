import AppKit
import SwiftUI

/// Emoji of a folder or Space icon: a field that accepts only an emoji (the last one typed or chosen replaces the
/// old one, a letter is refused, emptying it restores the default icon) and “Emoji & Symbols…”, which opens the
/// system's Character Viewer on this field.
struct IconEmojiField: View {
    /// Emoji of the current icon, nil if it is not one.
    let emoji: String?
    /// Prefix of the accessibility identifiers: “<prefix>Field” and “<prefix>PaletteButton”.
    let identifierPrefix: String
    /// Esc in the field: closes the panel or the popover that contains it.
    let close: () -> Void
    /// New emoji, or nil to go back to the default icon.
    let choose: (String?) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(text: $draft, prompt: Text("Emoji")) {
                Text("Emoji", comment: "Icon of a folder or a Space: field that takes one emoji as the icon")
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 56)
            .focused($isFocused)
            .onExitCommand(perform: close)
            .onAppear { draft = emoji ?? "" }
            .onChange(of: emoji) { _, value in draft = value ?? "" }
            .onChange(of: draft) { _, text in accept(text) }
            .help("Type or paste one emoji")
            .accessibilityIdentifier("\(identifierPrefix)Field")
            Button("Emoji & Symbols…", action: showCharacterViewer)
                .controlSize(.small)
                .help("Choose an emoji in the Character Viewer")
                .accessibilityIdentifier("\(identifierPrefix)PaletteButton")
            Spacer(minLength: 0)
        }
    }

    private func accept(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Field emptied: the default icon; whitespace alone is erased.
            if !text.isEmpty {
                draft = ""
            }
            if emoji != nil {
                choose(nil)
            }
        } else if let latest = IconEmoji.latest(in: text) {
            if draft != latest {
                draft = latest
            }
            if latest != emoji {
                choose(latest)
            }
        } else {
            // Not an emoji: the field goes back to the current icon.
            draft = emoji ?? ""
        }
    }

    /// The viewer inserts the chosen emoji into the field that has the keyboard: the field takes it first.
    private func showCharacterViewer() {
        isFocused = true
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}
