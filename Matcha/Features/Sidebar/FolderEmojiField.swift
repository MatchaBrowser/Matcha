import AppKit
import SwiftUI

/// Emoji de l'icône d'un dossier : un champ qui n'accepte qu'un emoji (le dernier tapé ou choisi remplace l'ancien,
/// une lettre est refusée, le vider rend l'icône par défaut) et « Emoji et symboles… », qui ouvre le visualiseur de
/// caractères du système sur ce champ.
struct FolderEmojiField: View {
    /// Emoji de l'icône actuelle, nil si elle n'en est pas un.
    let emoji: String?
    /// Échap dans le champ : ferme le panneau.
    let close: () -> Void
    /// Nouvel emoji, ou nil pour revenir à l'icône par défaut.
    let choose: (String?) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(text: $draft, prompt: Text("Emoji")) {
                Text("Emoji", comment: "Folder customization: field that takes one emoji as the folder icon")
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
            .accessibilityIdentifier("folderEmojiField")
            Button("Emoji & Symbols…", action: showCharacterViewer)
                .controlSize(.small)
                .help("Choose an emoji in the Character Viewer")
                .accessibilityIdentifier("folderEmojiPaletteButton")
            Spacer(minLength: 0)
        }
    }

    private func accept(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Champ vidé : l'icône par défaut ; des espaces seuls sont effacés.
            if !text.isEmpty {
                draft = ""
            }
            if emoji != nil {
                choose(nil)
            }
        } else if let latest = FolderEmoji.latest(in: text) {
            if draft != latest {
                draft = latest
            }
            if latest != emoji {
                choose(latest)
            }
        } else {
            // Pas un emoji : le champ revient à l'icône actuelle.
            draft = emoji ?? ""
        }
    }

    /// Le visualiseur insère l'emoji choisi dans le champ qui a le clavier : le champ le prend d'abord.
    private func showCharacterViewer() {
        isFocused = true
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.orderFrontCharacterPalette(nil)
        }
    }
}
