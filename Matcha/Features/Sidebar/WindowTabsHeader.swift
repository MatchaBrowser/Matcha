import SwiftUI

/// Header of a window of its own tabs (a detached tab, Arc's “This Window”): its title, and “Move to…”, which gives its
/// tabs to a Space; the window then shows that Space.
struct WindowTabsHeader: View {
    let model: WindowModel

    var body: some View {
        HStack(spacing: 8) {
            Text("This Window", comment: "Sidebar title of a window holding only its own tabs, outside any Space")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Menu {
                ForEach(model.session.spaces) { space in
                    Button(space.record.name) {
                        withMotion(.easeInOut(duration: 0.3)) { model.moveWindowTabs(to: space) }
                    }
                }
            } label: {
                Text("Move to…", comment: "Sidebar menu of a window of its own tabs: moves them into a Space")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .help(Text("Move this window's tabs to a Space", comment: "Help tag of the “Move to…” menu of a window of its own tabs"))
            .accessibilityIdentifier("moveWindowTabs")
        }
        .padding(.leading, 8)
        .frame(height: 24)
    }
}
