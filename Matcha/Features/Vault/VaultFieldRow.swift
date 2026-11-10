import SwiftUI

/// A field of an item: its label, its value, a button that copies it; a secret is masked until shown, and copied as a
/// secret (`VAULT.md` § 7.5).
struct VaultFieldRow: View {
    let label: String
    let value: String
    var isSecret = false
    var isMonospaced = false
    let clipboard: VaultClipboard
    @State private var isShown = false

    var body: some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if isSecret, !isShown {
                        Text(String(repeating: "•", count: min(max(value.count, 8), 16)))
                    } else {
                        Text(value)
                            .textSelection(.enabled)
                    }
                }
                .font(isMonospaced ? .body.monospaced() : .body)
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSecret {
                    Button {
                        isShown.toggle()
                    } label: {
                        Image(systemName: isShown ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isShown
                        ? String(localized: "Hide", comment: "Vault: button that masks a secret")
                        : String(localized: "Show", comment: "Vault: button that reveals a secret"))
                }
                Button {
                    clipboard.copy(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Copy", comment: "Vault: button that copies a field"))
            }
        } label: {
            Text(label)
        }
    }
}

/// A one-time code, live: the code of now and the seconds left, copied as a secret. Codes come from this Mac's clock.
struct VaultOneTimeCodeRow: View {
    let code: OneTimeCode
    let clipboard: VaultClipboard

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let value = code.code(at: context.date)
            LabeledContent {
                HStack {
                    Text(Self.grouped(value))
                        .font(.title3.monospacedDigit())
                        .textSelection(.enabled)
                    Text("\(code.secondsRemaining(at: context.date)) s", comment: "Vault: seconds left of a one-time code")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Button {
                        clipboard.copy(value)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Copy", comment: "Vault: button that copies a field"))
                }
            } label: {
                Text("One-Time Code", comment: "Vault: field of a login, the secret of a TOTP code or an otpauth address")
            }
        }
    }

    /// `123 456`, `1234 5678`: easier to read.
    static func grouped(_ code: String) -> String {
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return "\(code[..<middle]) \(code[middle...])"
    }
}
