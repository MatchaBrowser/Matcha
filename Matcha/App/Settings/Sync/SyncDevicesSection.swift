import SwiftUI

/// Settings > Sync: the account's devices (task 7.9). Disconnecting one revokes its tokens; it keeps its data and asks
/// for the password again.
struct SyncDevicesSection: View {
    let sync: SyncService

    @State private var devices: [SyncDevice] = []
    @State private var revoked: SyncDevice?
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ForEach(devices) { device in
                HStack {
                    Image(systemName: "laptopcomputer")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: device.name)
                        if device.current == true {
                            Text("This Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let seen = device.lastSeenAt {
                            Text("Last seen \(seen.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if device.current != true {
                        Button("Disconnect…") { revoked = device }
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Devices")
        } footer: {
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await load() }
        .confirmationDialog(
            "Disconnect “\(revoked?.name ?? "")”?",
            isPresented: Binding { revoked != nil } set: {
                if !$0 {
                    revoked = nil
                }
            },
        ) {
            Button("Disconnect", role: .destructive) {
                if let device = revoked {
                    Task { await revoke(device) }
                }
            }
        } message: {
            Text("It stops syncing and keeps its data. Signing in again reconnects it.")
        }
    }

    private func load() async {
        do {
            devices = try await sync.devices()
            errorMessage = nil
        } catch {
            errorMessage = SyncErrorText.message(for: error)
        }
    }

    private func revoke(_ device: SyncDevice) async {
        do {
            try await sync.revokeDevice(device.id)
            await load()
        } catch {
            errorMessage = SyncErrorText.message(for: error)
        }
    }
}
