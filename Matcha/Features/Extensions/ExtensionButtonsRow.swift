import SwiftUI
import WebKit

/// Boutons des extensions (tâche 6.5) : un par extension chargée dont le bouton n'est pas masqué ; dans une fenêtre
/// privée, seulement celles qui y ont accès. Ils visent `tab` (onglet affiché, aperçu compris, ou panneau de la carte).
/// Rien sans extension à montrer.
struct ExtensionButtonsRow: View {
    let tab: BrowserTab?
    let isPrivate: Bool
    var manager = ExtensionManager.shared

    var body: some View {
        let extensions = manager.buttonExtensions(isPrivate: isPrivate)
        if !extensions.isEmpty {
            HStack(spacing: 2) {
                ForEach(extensions, id: \.identifier) { item in
                    ExtensionActionButton(identifier: item.identifier, tab: tab, manager: manager)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("extensionButtons")
        }
    }
}

/// Bouton d'une extension : icône de son action pour l'onglet visé, badge de texte, titre en info-bulle ; menu
/// contextuel (options, masquer le bouton, gérer les extensions). Sa bulle s'ouvre dessous.
struct ExtensionActionButton: View {
    static let iconSize = CGSize(width: 16, height: 16)

    let identifier: String
    let tab: BrowserTab?
    let manager: ExtensionManager

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let action = manager.action(of: identifier, for: tab)
        let context = manager.contexts[identifier]
        let name = context.map(ExtensionManager.name(of:)) ?? identifier
        Button {
            manager.performAction(of: identifier, for: tab)
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
        .background(ExtensionButtonAnchor(identifier: identifier, tabID: tabID, anchors: manager.buttonAnchors))
        .contextMenu {
            if context?.optionsPageURL != nil {
                Button("Options…") { manager.openOptionsPage(identifier: identifier) }
            }
            Button("Hide Button") { manager.setShowsButton(false, identifier: identifier) }
            Divider()
            Button("Manage Extensions…") {
                SettingsSelection.shared.tab = .extensions
                openSettings()
            }
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: action?.badgeText ?? ""))
        .accessibilityIdentifier("extensionButton")
    }

    /// Onglet visé, tel que WebKit le connaît (pour ancrer la bulle sous ce bouton-ci).
    private var tabID: UUID? {
        tab.flatMap { manager.windows.adapter(for: $0)?.tabID }
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

    /// Badge de texte de l'action (nombre de publicités bloquées, de mots de passe…) ; plus vif s'il n'a pas été vu.
    @ViewBuilder private func badge(_ action: WKWebExtension.Action?) -> some View {
        if let action, !action.badgeText.isEmpty {
            Text(verbatim: action.badgeText)
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

/// Vue AppKit derrière un bouton d'extension, inscrite dans `ExtensionButtonAnchors` pour y ancrer sa bulle.
private struct ExtensionButtonAnchor: NSViewRepresentable {
    let identifier: String
    let tabID: UUID?
    let anchors: ExtensionButtonAnchors

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        anchors.register(view, identifier: identifier, tabID: tabID)
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        anchors.register(view, identifier: identifier, tabID: tabID)
    }

    static func dismantleNSView(_ view: NSView, coordinator _: ()) {
        ExtensionManager.shared.buttonAnchors.unregister(view)
    }
}
