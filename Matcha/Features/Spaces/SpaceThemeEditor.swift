import SwiftUI

/// Theme of a Space, a section of its editor (`SpaceEditor`): predefined themes, free colors (2 or 3) and the
/// gradient's angle.
struct SpaceThemeEditor: View {
    @Binding var theme: SpaceTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SpaceEditorSectionTitle(Text("Theme", comment: "Space editor: title of the theme section"))
                HStack(spacing: 10) {
                    ForEach(SpaceTheme.presets, id: \.self) { preset in
                        presetButton(preset)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                ForEach(theme.colors.indices, id: \.self) { index in
                    ColorPicker("Color \(index + 1)", selection: colorBinding(at: index), supportsOpacity: false)
                        .labelsHidden()
                }
                Spacer()
                Button("Remove Color", systemImage: "minus") { setColors(Array(theme.colors.dropLast())) }
                    .disabled(theme.colors.count <= SpaceTheme.colorCountRange.lowerBound)
                Button("Add Color", systemImage: "plus") { addColor() }
                    .disabled(theme.colors.count >= SpaceTheme.colorCountRange.upperBound)
            }
            .labelStyle(.iconOnly)
            LabeledContent("Angle") {
                Slider(value: $theme.angle, in: 0 ... 360, step: 15)
            }
        }
    }

    private func presetButton(_ preset: SpaceTheme) -> some View {
        let name = preset.displayName.map { Text($0) } ?? Text(verbatim: "")
        return Button {
            theme = SpaceTheme(name: preset.name, colors: preset.colors, angle: theme.angle)
        } label: {
            Circle()
                // Base colors, vivid: the dark variants are hard to tell apart at small size.
                .fill(LinearGradient(colors: preset.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.primary.opacity(theme.name == preset.name ? 0.9 : 0.15), lineWidth: 2))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityIdentifier("themePreset")
    }

    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding {
            theme.colors[index].color
        } set: { color in
            var colors = theme.colors
            colors[index] = ThemeColor(color)
            setColors(colors)
        }
    }

    private func addColor() {
        let last = theme.colors.last ?? .white
        setColors(theme.colors + [last.mixed(with: .white, amount: 0.3)])
    }

    private func setColors(_ colors: [ThemeColor]) {
        var edited = theme
        edited.setColors(colors)
        theme = edited
    }
}
