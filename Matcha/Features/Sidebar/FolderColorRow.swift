import SwiftUI

/// One color of a folder (text or background) in its panel: title and system picker for any color, then the
/// swatches: “No Color” and the colors of `FolderColorPreset`. The chosen color is circled.
struct FolderColorRow: View {
    static let swatchSize = 13.0
    /// Swatch and selection ring.
    static let cellSize = 18.0
    /// Color of the picker as long as none is chosen.
    private static let unsetPickerColor = ThemeColor(red: 0.5, green: 0.5, blue: 0.5)

    let title: LocalizedStringKey
    /// Name of the color picker for VoiceOver and in the tooltip.
    let pickerTitle: LocalizedStringKey
    let selection: ThemeColor?
    /// Prefix of the accessibility identifiers: “<prefix>.red”, “<prefix>.none”, “<prefix>Picker”.
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

    /// A color outside the swatches, chosen in the system picker, in sRGB.
    private var pickerBinding: Binding<Color> {
        Binding {
            (selection ?? Self.unsetPickerColor).color
        } set: { color in
            choose(ThemeColor(color))
        }
    }

    /// Swatch of a color from the swatches, or “No Color” (`preset` nil: the system's color).
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
                        .overlay(Circle().strokeBorder(.hairline, lineWidth: 1))
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
