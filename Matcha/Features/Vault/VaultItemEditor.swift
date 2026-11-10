import SwiftUI

/// The form of an item being created or changed: its title, the fields of its category, its addresses, tags, notes and
/// custom fields. What the form doesn't show stays as it was (`VaultItemDraft`).
struct VaultItemEditor: View {
    @Binding var draft: VaultItemDraft
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Title", comment: "Vault editor: title of the item"), text: $draft.title)
                Toggle(String(localized: "Favorite", comment: "Vault editor"), isOn: $draft.favorite)
                if draft.category == .document {
                    Picker(String(localized: "Kind", comment: "Vault editor: kind of document"), selection: $draft.documentType) {
                        ForEach(VaultFieldSpec.documentTypes, id: \.self) { Text(VaultFieldSpec.documentName($0)).tag($0) }
                    }
                }
            }
            if draft.category == .sshKey {
                VaultSSHKeySection(draft: $draft)
            }
            if !draft.specs.isEmpty {
                Section {
                    ForEach(draft.specs, id: \.id) { spec in
                        VaultFieldEditor(spec: spec, value: binding(for: spec))
                    }
                }
            }
            if draft.category == .login {
                VaultURLsSection(urls: $draft.urls, match: $draft.match)
            }
            VaultCustomFieldsEditor(fields: $draft.fields)
            VaultFilesEditor(files: $draft.files)
            Section(String(localized: "Notes", comment: "Vault: notes of an item")) {
                TextEditor(text: $draft.notes)
                    .frame(minHeight: 80)
                    .font(.body)
            }
            Section(String(localized: "Tags", comment: "Vault window: sidebar section")) {
                TextField(
                    String(localized: "Tags, separated by commas", comment: "Vault editor"),
                    text: Binding { draft.tags.joined(separator: ", ") } set: { draft.tags = $0.components(separatedBy: ",") },
                )
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(String(localized: "Cancel", comment: "Vault editor"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Save", comment: "Vault editor"), action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }
    }

    private func binding(for spec: VaultFieldSpec) -> Binding<String> {
        Binding { draft.values[spec.id] ?? "" } set: { draft.values[spec.id] = $0 }
    }
}

/// A field of the form: a text, a secret with the generator for a password, or a read-only value.
struct VaultFieldEditor: View {
    let spec: VaultFieldSpec
    @Binding var value: String
    @State private var showsGenerator = false

    var body: some View {
        switch spec.kind {
        case .secret:
            HStack {
                SecureField(spec.label, text: $value)
                if spec.key == "password" {
                    Button {
                        showsGenerator = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Generate a Password", comment: "Vault editor: opens the generator"))
                    .popover(isPresented: $showsGenerator) {
                        VaultGeneratorView { generated in
                            value = generated
                            showsGenerator = false
                        }
                    }
                }
            }
        case .secretText:
            LabeledContent(spec.label) {
                TextEditor(text: $value).font(.caption.monospaced()).frame(minHeight: 80)
            }
        case .readOnly:
            LabeledContent(spec.label) { Text(value).font(.caption.monospaced()).textSelection(.enabled) }
        case .month:
            TextField(spec.label, text: $value, prompt: Text(verbatim: "2030-12"))
        case .date:
            TextField(spec.label, text: $value, prompt: Text(verbatim: "2030-12-31"))
        case .oneTimeCode:
            TextField(spec.label, text: $value, prompt: Text("Secret or otpauth:// address", comment: "Vault editor: one-time code field"))
        case .text:
            TextField(spec.label, text: $value)
        }
    }
}

/// The addresses of a login and how pages match them (`VAULT.md` § 8.2).
struct VaultURLsSection: View {
    @Binding var urls: [String]
    @Binding var match: VaultURLMatch

    var body: some View {
        Section(String(localized: "Websites", comment: "Vault: addresses of a login")) {
            ForEach(urls.indices, id: \.self) { index in
                HStack {
                    TextField(String(localized: "Address", comment: "Vault editor: a website address"), text: $urls[index])
                    Button(role: .destructive) { urls.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button(String(localized: "Add a Website", comment: "Vault editor")) { urls.append("") }
            Picker(String(localized: "Fill on", comment: "Vault editor: how a login matches pages"), selection: $match) {
                ForEach(VaultURLMatch.allCases, id: \.self) { Text($0.name).tag($0) }
            }
        }
        .onAppear {
            if urls.isEmpty {
                urls = [""]
            }
        }
    }
}

/// The custom fields of an item: a label, a type, a value.
struct VaultCustomFieldsEditor: View {
    @Binding var fields: [VaultEntry]

    var body: some View {
        Section(String(localized: "Fields", comment: "Vault editor: custom fields")) {
            ForEach(fields.indices, id: \.self) { index in
                HStack {
                    TextField(String(localized: "Label", comment: "Vault editor: name of a custom field"), text: string(index, "label"))
                        .frame(maxWidth: 140)
                    Picker(String(), selection: string(index, "type")) {
                        ForEach(VaultFieldType.allCases, id: \.self) { Text($0.name).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)
                    if VaultFieldType(rawValue: fields[index].string("type"))?.isSecret == true {
                        SecureField(String(), text: string(index, "value"))
                    } else {
                        TextField(String(), text: string(index, "value"))
                    }
                    Button(role: .destructive) { fields.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button(String(localized: "Add a Field", comment: "Vault editor")) {
                var entry = VaultEntry(["type": .string(VaultFieldType.text.rawValue)])
                entry.id = VaultEntryID.make()
                fields.append(entry)
            }
        }
    }

    private func string(_ index: Int, _ key: String) -> Binding<String> {
        Binding { fields[index].string(key) } set: { fields[index].set(key, $0) }
    }
}
