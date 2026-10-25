import SwiftUI
import WebKit

/// Extension buttons (task 6.5): one per loaded extension whose button is not hidden; in a private window, only those
/// that have access to it. They target `tab` (displayed tab, peek included, or pane of the card).
/// Nothing when there is no extension to show.
struct ExtensionButtonsRow: View {
    let tab: BrowserTab?
    let isPrivate: Bool
    @Environment(ExtensionManager.self) private var manager
    @Environment(\.extensionWindows) private var windows

    var body: some View {
        let extensions = manager.toolbar.buttonExtensions(isPrivate: isPrivate)
        if !extensions.isEmpty, let windows {
            HStack(spacing: 2) {
                ForEach(extensions, id: \.identifier) { item in
                    ExtensionActionButton(identifier: item.identifier, tab: tab, manager: manager, windows: windows)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("extensionButtons")
        }
    }
}

/// Button of an extension: icon of its action for the target tab, text badge, title as tooltip; context menu
/// (options, hide the button, manage extensions). Its popover opens below it.
struct ExtensionActionButton: View {
    static let iconSize = CGSize(width: 16, height: 16)

    let identifier: String
    let tab: BrowserTab?
    let manager: ExtensionManager
    let windows: ExtensionWindows

    @Environment(\.openSettings) private var openSettings
    @Environment(SettingsSelection.self) private var settingsSelection

    var body: some View {
        let action = manager.toolbar.action(of: identifier, for: tab)
        let context = manager.contexts[identifier]
        let name = context.map(ExtensionToolbar.name(of:)) ?? identifier
        Button {
            manager.toolbar.performAction(of: identifier, for: tab)
        } label: {
            Label {
                Text(verbatim: name)
            } icon: {
                icon(action?.icon(for: Self.iconSize) ?? context?.webExtension.icon(for: Self.iconSize))
            }
        }
        .overlay(alignment: .topTrailing) { badge(action) }
        .disabled(action.map { !$0.isEnabled } ?? false)
        .help(action.flatMap { $0.label.isEmpty ? nil : $0.label } ?? name)
        .background(ExtensionButtonAnchor(identifier: identifier, tabID: tabID, anchors: windows.buttonAnchors))
        .contextMenu {
            if context?.optionsPageURL != nil {
                Button("Options…") { manager.openOptionsPage(identifier: identifier) }
            }
            Button("Hide Button") { manager.toolbar.setShowsButton(false, identifier: identifier) }
            Divider()
            Button("Manage Extensions…") {
                settingsSelection.tab = .extensions
                openSettings()
            }
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: action?.badgeText ?? ""))
        .accessibilityIdentifier("extensionButton")
    }

    /// Target tab, as WebKit knows it (to anchor the popover under this very button).
    private var tabID: UUID? {
        tab.flatMap { windows.adapter(for: $0)?.tabID }
    }

    @ViewBuilder private func icon(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .frame(width: Self.iconSize.width, height: Self.iconSize.height)
        } else {
            Image(systemName: "puzzlepiece.extension")
        }
    }

    /// Text badge of the action (number of blocked ads, of passwords…); brighter if it has not been seen.
    @ViewBuilder private func badge(_ action: WKWebExtension.Action?) -> some View {
        if let action, !ExtensionDisplayName.badge(action.badgeText).isEmpty {
            Text(verbatim: ExtensionDisplayName.badge(action.badgeText))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 3)
                .frame(minWidth: 12, minHeight: 11)
                .background(Capsule().fill(action.hasUnreadBadgeText ? Color.accentColor : Color.secondary))
                .offset(x: 2, y: -1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// AppKit view behind an extension button, registered in `ExtensionButtonAnchors` to anchor its popover there.
private struct ExtensionButtonAnchor: NSViewRepresentable {
    let identifier: String
    let tabID: UUID?
    let anchors: ExtensionButtonAnchors

    func makeCoordinator() -> ExtensionButtonAnchors {
        anchors
    }

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchors.register(view, identifier: identifier, tabID: tabID)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        anchors.register(view, identifier: identifier, tabID: tabID)
    }

    static func dismantleNSView(_ view: NSView, coordinator anchors: ExtensionButtonAnchors) {
        anchors.unregister(view)
    }
}
