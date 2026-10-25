import SwiftUI

/// Strength of the new password, and the reminder that it can't be recovered.
struct SyncPasswordGauge: View {
    let strength: SyncPasswordStrength
    let mismatch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Gauge(value: Double(strength.rawValue), in: 0 ... 4) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(color)
            .accessibilityLabel(Text("Password strength"))
            .accessibilityValue(label)
            (mismatch ? Text("The two passwords are different.") : label)
                .font(.caption)
                .foregroundStyle(mismatch ? .red : .secondary)
            Text("Matcha can't recover this password. Without it or the recovery kit, your synced data is lost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var label: Text {
        switch strength {
        case .tooShort: Text("At least 12 characters.")
        case .weak: Text("Weak: add words, numbers or symbols.")
        case .fair: Text("Fair")
        case .good: Text("Good")
        case .strong: Text("Strong")
        }
    }

    private var color: Color {
        switch strength {
        case .tooShort, .weak: .red
        case .fair: .orange
        case .good: .yellow
        case .strong: .green
        }
    }
}
