/// Sensitive operations on the sync account (`SYNC.md` § 4.1): they ask for the master password again.
enum SyncAccountAction: String, Identifiable {
    case changePassword
    case newRecoveryKit
    case changeEmail
    case deleteAccount

    var id: String {
        rawValue
    }
}
