import Foundation

/// What Settings > Sync warns about (review TS12: the section's rules, tested apart): refused records, full account,
/// recovery kit not saved, unreadable data, and the clocks of this Mac and the others.
@MainActor
enum SyncWarnings {
    static func list(
        state: SyncState?,
        isRecoveryKitUnsaved: Bool,
        hasPendingKit: Bool,
        clockOffset: TimeInterval?,
        now: Date = .now,
    ) -> [String] {
        var warnings: [String] = []
        if let state {
            let tooLarge = state.rejected.values.count { $0.code == SyncRejectionCode.payloadTooLarge }
            if tooLarge > 0 {
                warnings.append(String(localized: "\(tooLarge) items are too big to sync."))
            }
            if state.isQuotaExceeded {
                warnings.append(String(localized: "The account's space is full: new changes wait on this Mac."))
            }
            if isRecoveryKitUnsaved, !hasPendingKit {
                warnings.append(String(
                    localized: "Your recovery kit wasn't saved: make a new one in Manage Account.",
                    comment: "Settings > Sync: warning when a new recovery key was made but its kit wasn't saved",
                ))
            }
            if state.showsFutureDateWarning(now: now) {
                warnings.append(String(localized: "The clock of one of your Macs seems to be ahead."))
            }
            if state.entries.values.contains(where: \.isUnreadable) {
                warnings.append(String(localized: "Some synced data is unreadable and was left aside."))
            }
        }
        if let offset = clockOffset, abs(offset) > SyncService.clockWarningGap {
            warnings.append(offset > SyncService.maximumClockLead
                ? String(localized: "This Mac's clock is more than a day ahead: nothing is sent until it is corrected.")
                : String(localized: "This Mac's clock is off. Check the date and time in System Settings."))
        }
        return warnings
    }
}
