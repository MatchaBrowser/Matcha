import SwiftUI

/// Une couleur d'un dossier (texte ou fond) dans son panneau : titre et sélecteur du système pour toute couleur, puis
/// le nuancier : « Aucune couleur » et les couleurs de `FolderColorPreset`. La couleur choisie est entourée.
struct FolderColorRow: View {
    static let swatchSize = 13.0
    /// Pastille et anneau de sélection.
    static let cellSize = 18.0
    /// Couleur du sélecteur tant qu'aucune n'est choisie.
    private static let unsetPickerColor = ThemeColor(red: 0.5, green: 0.5, blue: 0.5)

    let title: LocalizedStringKey
    /// Nom du sélecteur de couleur pour VoiceOver et en bulle d'aide.
    let pickerTitle: LocalizedStringKey
    let selection: ThemeColor?
    /// Préfixe des identifiants d'accessibilité : « <préfixe>.red », « <préfixe>.none », « <préfixe>Picker ».
    let identifier: String
    let choose: (ThemeColor?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ColorPicker(selection: pickerBinding, supportsOpacity: false) { Text(pickerTitle) }
                    .labelsHidden()
                    .controlSize(.small)
                    .help(Text(pickerTitle))
                    .accessibilityIdentifier("\(identifier)Picker")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cellSize, maximum: Self.cellSize + 4), spacing: 2)], spacing: 4) {
                swatch(nil)
                ForEach(FolderColorPreset.all) { preset in
                    swatch(preset)
                }
            }
        }
    }

    /// Une couleur hors du nuancier, choisie dans le sélecteur du système, en sRGB.
    private var pickerBinding: Binding<Color> {
        Binding {
            (selection ?? Self.unsetPickerColor).color
        } set: { color in
            choose(ThemeColor(color))
        }
    }

    /// Pastille d'une couleur du nuancier, ou « Aucune couleur » (`preset` nil : celle du système).
    private func swatch(_ preset: FolderColorPreset?) -> some View {
        let isSelected = preset?.color == selection
        let name = preset.map { Text($0.title) } ?? Text("No Color", comment: "Folder color swatch: use the system color")
        return Button {
            choose(preset?.color)
        } label: {
            Group {
                if let preset {
                    Circle()
                        .fill(preset.color.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                } else {
                    Image(systemName: "circle.slash")
                        .font(.system(size: Self.swatchSize - 1))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: Self.swatchSize, height: Self.swatchSize)
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.85 : 0), lineWidth: 1.5))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifier).\(preset?.id ?? "none")")
    }
}
