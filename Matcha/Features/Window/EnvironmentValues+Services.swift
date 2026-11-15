import SwiftUI

/// Objects of the app's composition root (`AppEnvironment`) that views reach but don't observe (audit C2).
extension EnvironmentValues {
    /// The windows as extensions see them; nil: extensions see no window.
    @Entry var extensionWindows: ExtensionWindows?
    /// Edit > Find on the pages of the active window.
    @Entry var pageFind: PageFindResponder?
    /// Where the vault copies its secrets (`VAULT.md` § 7.5); nil: nothing is copied (previews).
    @Entry var vaultClipboard: VaultClipboard?
}
