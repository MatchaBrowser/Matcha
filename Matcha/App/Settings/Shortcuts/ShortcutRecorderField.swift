import SwiftUI

/// Shortcut of a menu command in Settings > Shortcuts: a click, then the new shortcut (`ShortcutRecorder`); the arrow
/// brings back the default one. A refused shortcut is explained underneath.
struct ShortcutRecorderField: View {
    let command: MenuShortcut
    private let store = MenuShortcutStore.shared
    private let recorder = ShortcutRecorder.shared

    private var isRecording: Bool {
        recorder.command == command
    }

    private var shortcutText: String {
        if isRecording {
            return String(localized: "Type Shortcut", comment: "Settings > Shortcuts: waiting for the new shortcut")
        }
        return store.key(for: command)?.displayText ?? String(
            localized: "None",
            comment: "Settings > Shortcuts: a command without shortcut",
        )
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                if store.isCustomized(command) {
                    Button {
                        recorder.stop()
                        store.reset(command)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Restore Default Shortcut"))
                    .accessibilityLabel(Text("Restore Default Shortcut"))
                }
                Button {
                    recorder.toggle(command, in: store)
                } label: {
                    Text(shortcutText)
                        .frame(minWidth: 90)
                        .foregroundStyle(isRecording ? Color.accentColor : .primary)
                }
                .accessibilityLabel(Text(command.title))
                .accessibilityValue(Text(shortcutText))
                .accessibilityHint(Text("Records a new shortcut.", comment: "Settings > Shortcuts: VoiceOver hint of a shortcut button"))
            }
            if let refusal = recorder.refusal, refusal.command == command {
                Text(refusal.problem.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
