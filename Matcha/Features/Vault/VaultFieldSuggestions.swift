import SwiftUI

/// The native list under the login field the user just reached (`VAULT.md` § 8.1), drawn by Matcha over the page, which
/// can neither cover nor restyle it: the logins of the site, or the vault to unlock. Nothing shows when the vault has
/// no login for the site. Placed by `VaultSuggestionPlacement`.
struct VaultFieldSuggestions: View {
    let tab: BrowserTab
    @Environment(VaultService.self) private var vault: VaultService?
    @State private var height: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            if let vault, let field = fieldBox(in: geometry.size, vault: vault), let frame = tab.vaultForms.mainFrame {
                let candidates = vault.isUnlocked ? vault.logins(for: tab.documentURL ?? frame.url) : []
                if !vault.isUnlocked || !candidates.isEmpty {
                    let list = VaultSuggestionPlacement.listFrame(for: field, height: height, in: geometry.size)
                    VaultSuggestionList(tab: tab, frame: frame, vault: vault, candidates: candidates)
                        // Another field, or the same one reached again: a new list, whose clicks wait again.
                        .id(tab.vaultForms.focusedField)
                        .frame(width: list.width)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
                        .offset(x: list.minX, y: list.minY)
                }
            }
        }
        // The tab no longer shown: its list doesn't come back with it.
        .onDisappear { tab.vaultForms.focusedField = nil }
    }

    /// The field reached, in the page's points, when the vault is offered and the field in sight.
    private func fieldBox(in size: CGSize, vault: VaultService) -> CGRect? {
        guard vault.isOffered, let place = tab.vaultForms.focusedField else {
            return nil
        }
        return VaultSuggestionPlacement.fieldBox(place, in: size)
    }
}

/// The rows of the list, which ↓, ↑ and ↩ also choose from (`BrowserWebView+VaultKeys`). They ignore clicks (and ↩)
/// in their first half second: a field focused under the pointer by the page doesn't take the click meant for
/// something else (clickjacking).
private struct VaultSuggestionList: View {
    let tab: BrowserTab
    let frame: VaultPageForms.Frame
    let vault: VaultService
    let candidates: [VaultFillCandidate]
    @Environment(\.vaultClipboard) private var clipboard
    @State private var shownAt = Date.now
    @State private var isUnlocking = false
    /// This list, for the rows it gives to the keyboard (`VaultPageForms.suggestionRows`).
    @State private var owner = UUID()

    static let maximumRows = 6
    static let clickDelay: TimeInterval = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if vault.isUnlocked {
                ForEach(Array(candidates.prefix(Self.maximumRows).enumerated()), id: \.element.id) { index, candidate in
                    row(index) { VaultFillRow(candidate: candidate) }
                }
            } else if isUnlocking {
                VaultQuickUnlock(vault: vault).padding(6)
            } else {
                row(0) {
                    Label {
                        Text("The vault is locked", comment: "Vault window: title of the lock screen")
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .onAppear {
            shownAt = .now
            giveRows()
        }
        .onChange(of: rowIDs) { giveRows() }
        // Opened with its password typed here: the keyboard goes back to the page, for ↓ and ↑.
        .onChange(of: vault.isUnlocked) { _, isUnlocked in
            if isUnlocked, isUnlocking {
                tab.webView?.focusPage()
            }
        }
        .onDisappear {
            if tab.vaultForms.suggestionRows?.owner == owner {
                tab.vaultForms.suggestionRows = nil
                tab.vaultForms.highlightedRow = nil
            }
        }
    }

    private func row(_ index: Int, @ViewBuilder label: () -> some View) -> some View {
        VaultSuggestionRow(isHighlighted: tab.vaultForms.highlightedRow == index, action: { choose(index) }, label: label)
            .onHover { inside in
                if inside {
                    tab.vaultForms.highlightedRow = index
                }
            }
    }

    /// What the rows are: the logins shown, the vault to unlock, or none while its password is typed.
    private var rowIDs: [String] {
        if vault.isUnlocked {
            return candidates.prefix(Self.maximumRows).map(\.id.uuidString)
        }
        return isUnlocking ? [] : ["locked"]
    }

    /// The rows go to the keyboard (↓, ↑, ↩), none highlighted.
    private func giveRows() {
        tab.vaultForms.highlightedRow = nil
        tab.vaultForms.suggestionRows = .init(owner: owner, count: rowIDs.count) { index in choose(index) }
    }

    private var isSettled: Bool {
        Date.now.timeIntervalSince(shownAt) >= Self.clickDelay
    }

    /// Fills the login of a row, or unlocks the vault from its row.
    private func choose(_ index: Int) {
        guard isSettled else {
            return
        }
        guard vault.isUnlocked else {
            unlock()
            return
        }
        guard candidates.indices.contains(index) else {
            return
        }
        tab.vaultForms.focusedField = nil
        VaultFillAction.fill(candidates[index], in: frame, tab: tab, vault: vault, clipboard: clipboard)
    }

    /// Touch ID when it may, the master password otherwise; the logins of the site show once it is open.
    private func unlock() {
        if VaultQuickUnlock.canUseTouchID(vault) {
            VaultQuickUnlock.unlockWithTouchID(vault)
        } else {
            isUnlocking = true
        }
    }
}

/// A row of the list, lit when highlighted (by the keyboard, or under the pointer).
private struct VaultSuggestionRow<Label: View>: View {
    let isHighlighted: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
