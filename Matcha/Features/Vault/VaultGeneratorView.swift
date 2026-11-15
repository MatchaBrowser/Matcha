import SwiftUI

/// The password generator (`VAULT.md` § 9.7): a password or a passphrase, drawn on the system's generator, with its
/// strength; “Use” puts it in the field.
struct VaultGeneratorView: View {
    let onUse: (String) -> Void
    @AppStorage("vaultGeneratorUsesWords") private var usesWords = false
    @AppStorage("vaultGeneratorLength") private var length = Double(PasswordGenerator.defaultLength)
    @AppStorage("vaultGeneratorWords") private var words = 5.0
    @AppStorage("vaultGeneratorSymbols") private var symbols = true
    @AppStorage("vaultGeneratorAvoidsAmbiguous") private var avoidsAmbiguous = false
    @State private var generated = ""
    @State private var bits = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(), selection: $usesWords) {
                Text("Password", comment: "Vault generator: random characters").tag(false)
                Text("Passphrase", comment: "Vault generator: random words").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(generated)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            Text("Strength: about \(Int(bits)) bits", comment: "Vault generator: entropy of the password")
                .font(.caption)
                .foregroundStyle(.secondary)
            if usesWords {
                Stepper(value: $words, in: 3 ... 12) {
                    Text("\(Int(words)) words", comment: "Vault generator: number of words")
                }
            } else {
                Slider(value: $length, in: 8 ... 100, step: 1) {
                    Text("\(Int(length)) characters", comment: "Vault generator: length")
                }
                Toggle(String(localized: "Symbols", comment: "Vault generator: use symbols"), isOn: $symbols)
                Toggle(String(localized: "Avoid look-alike characters", comment: "Vault generator: no 0 O 1 l I"), isOn: $avoidsAmbiguous)
            }
            HStack {
                Button(String(localized: "Generate Again", comment: "Vault generator"), action: generate)
                Spacer()
                Button(String(localized: "Use", comment: "Vault generator: put the password in the field")) { onUse(generated) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(generated.isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear(perform: generate)
        .onChange(of: usesWords) { generate() }
        .onChange(of: length) { generate() }
        .onChange(of: words) { generate() }
        .onChange(of: symbols) { generate() }
        .onChange(of: avoidsAmbiguous) { generate() }
    }

    private func generate() {
        do {
            if usesWords {
                let generator = try PassphraseGenerator(
                    wordlist: PassphraseWordlist.bundled(in: .main),
                    wordCount: Int(words),
                    separator: "-",
                    capitalizesWords: false,
                    includesDigit: true,
                )
                (generated, bits) = (generator.generate(), generator.entropyBits)
            } else {
                var classes: Set<PasswordGenerator.CharacterClass> = [.lowercase, .uppercase, .digits]
                if symbols {
                    classes.insert(.symbols)
                }
                let generator = try PasswordGenerator(
                    length: Int(length),
                    characterClasses: classes,
                    avoidsAmbiguousCharacters: avoidsAmbiguous,
                )
                (generated, bits) = (generator.generate(), generator.entropyBits)
            }
        } catch {
            generated = ""
        }
    }
}
