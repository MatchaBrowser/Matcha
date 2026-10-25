import Foundation
@testable import Matcha
import SwiftUI
import Testing

/// Rules taken out of the views (review TS12): account forms, sync warnings, sidebar presentation, page sheets, a
/// download's status, the place of a window and of a split's drop.
@MainActor
struct ViewRulesTests {
    private static let strong = "un mot de passe assez long, 2026"

    @Test func `account forms ask for what each step needs`() {
        #expect(!SyncFormRules.canSubmit(.signIn, email: " ", password: "x", confirmation: "", recoveryKey: ""))
        #expect(SyncFormRules.canSubmit(.signIn, email: "a@b.c", password: "x", confirmation: "", recoveryKey: ""))
        #expect(!SyncFormRules.canSubmit(.create, email: "a@b.c", password: "court", confirmation: "court", recoveryKey: ""))
        #expect(!SyncFormRules.canSubmit(.create, email: "a@b.c", password: Self.strong, confirmation: "autre", recoveryKey: ""))
        #expect(SyncFormRules.canSubmit(.create, email: "a@b.c", password: Self.strong, confirmation: Self.strong, recoveryKey: ""))
        #expect(!SyncFormRules.canSubmit(.recover, email: "a@b.c", password: Self.strong, confirmation: Self.strong, recoveryKey: "x"))

        #expect(!SyncFormRules.canConfirm(.deleteAccount, password: "", newPassword: "", confirmation: "", email: ""))
        #expect(SyncFormRules.canConfirm(.deleteAccount, password: "x", newPassword: "", confirmation: "", email: ""))
        #expect(!SyncFormRules.canConfirm(.changeEmail, password: "x", newPassword: "", confirmation: "", email: "sans-arobase"))
        #expect(SyncFormRules.canConfirm(.changePassword, password: "x", newPassword: Self.strong, confirmation: Self.strong, email: ""))
    }

    @Test func `sync warns about refused records, a full account, the kit and the clocks`() {
        #expect(SyncWarnings.list(state: nil, isRecoveryKitUnsaved: false, hasPendingKit: false, clockOffset: nil).isEmpty)
        var state = SyncState()
        state.rejected[UUID()] = SyncRejection(code: SyncRejectionCode.payloadTooLarge, local: .null)
        state.isQuotaExceeded = true
        let warnings = SyncWarnings.list(state: state, isRecoveryKitUnsaved: true, hasPendingKit: false, clockOffset: 3600)
        #expect(warnings.count == 4)
        // A kit about to be shown is no warning; a clock off by a few seconds neither.
        #expect(SyncWarnings.list(state: SyncState(), isRecoveryKitUnsaved: true, hasPendingKit: true, clockOffset: 5).isEmpty)
        let ahead = SyncWarnings.list(state: nil, isRecoveryKitUnsaved: false, hasPendingKit: false, clockOffset: 2 * 86400)
        #expect(ahead.count == 1)
    }

    @Test func `the sidebar's presentation gives the buttons and the card's margins`() {
        let fixed = SidebarPresentation(isSidebarVisible: true, isFloatingSidebarShown: false, hiddenSidebarStyle: .icons)
        #expect(!fixed.showsCompactSidebar && fixed.showsWindowButtons && fixed.cardPaddingEdges == [.top, .trailing, .bottom])
        let hidden = SidebarPresentation(isSidebarVisible: false, isFloatingSidebarShown: false, hiddenSidebarStyle: .hidden)
        #expect(!hidden.showsWindowButtons && hidden.cardPaddingEdges == .all)
        let floating = SidebarPresentation(isSidebarVisible: false, isFloatingSidebarShown: true, hiddenSidebarStyle: .hidden)
        #expect(floating.showsWindowButtons)
        let icons = SidebarPresentation(isSidebarVisible: false, isFloatingSidebarShown: false, hiddenSidebarStyle: .icons)
        #expect(icons.showsCompactSidebar && icons.showsWindowButtons && icons.cardPaddingEdges == [.trailing, .bottom])
        // The floating sidebar hides the start of the card: no split drop there.
        #expect(BrowserWindowView.splitDropInset(floatingWidth: nil, showsCompactSidebar: false) == 0)
        #expect(BrowserWindowView.splitDropInset(floatingWidth: 260, showsCompactSidebar: false) == 260 - BrowserWindowView.cardMargin)
        #expect(BrowserWindowView.splitDropInset(floatingWidth: 260, showsCompactSidebar: true) == 260 - CompactSidebar.width)
    }

    @Test func `a login sheet explains the area, a refused attempt and an unencrypted password`() {
        let plain = LoginRequest(site: "example.com", realm: nil, isSecure: true, failedBefore: false, user: nil)
        #expect(SystemPageDialogs.explanation(of: plain).isEmpty)
        let worried = LoginRequest(site: "http://router.local", realm: "Admin", isSecure: false, failedBefore: true, user: nil)
        let lines = SystemPageDialogs.explanation(of: worried).components(separatedBy: "\n\n")
        #expect(lines.count == 3)
        #expect(lines[0].contains("Admin"))
    }

    @Test func `a download's status follows its state`() {
        let failed = DownloadItem(saved: SavedDownload(id: UUID(), fileName: "a.zip", fileURL: nil, outcome: .failed, byteCount: 0))
        let cancelled = DownloadItem(saved: SavedDownload(id: UUID(), fileName: "a.zip", fileURL: nil, outcome: .cancelled, byteCount: 0))
        #expect(DownloadRow.status(of: failed) != DownloadRow.status(of: cancelled))
        let finished = DownloadItem(saved: SavedDownload(id: UUID(), fileName: "a.zip", fileURL: nil, outcome: .finished, byteCount: 2048))
        finished.checkFile()
        // No file: “not found”, never its size.
        #expect(!DownloadRow.status(of: finished).contains("KB"))
    }

    @Test func `a dropped tab's window lands under the pointer, in its sidebar`() {
        let origin = TabDragOutModifier.windowOrigin(forDropAt: CGPoint(x: 500, y: 400))
        #expect(origin.x < 500 && origin.y > 400)
    }
}
