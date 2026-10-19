import Foundation
import OSLog
import SwiftData

/// What to do when the store can't be opened or read (audit R2).
enum StoreFailureChoice: Sendable {
    case quit
    /// The unreadable store is put aside (never deleted) and a new one starts.
    case startOver
    /// Browsing goes on in memory: nothing is saved, as in a private window.
    case continueWithoutSaving
}

/// Opening the app's session.
extension BrowserSession {
    /// The app's session; nil if the user chose to quit. During tests, the store stays in memory: the user's tabs are
    /// neither read nor modified. A store that can't be opened or read is never replaced silently: `onFailure` (an
    /// alert) decides.
    static func launch(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        storeURL: URL? = nil,
        onFailure: @MainActor (any Error) -> StoreFailureChoice = StoreFailureAlert.ask,
    ) -> BrowserSession? {
        let inMemory = TestEnvironment.usesInMemoryStore(defaults: defaults, environment: environment)
        // UI tests' arguments: Debug builds only, never the default store (`TestEnvironment`, audit R6).
        let arguments = TestEnvironment.arguments(defaults)
        let name = arguments?.string(forKey: storeNameKey)
        if let name, arguments?.bool(forKey: resetStoreKey) == true, TestEnvironment.isResettableStore(named: name) {
            deleteStore(named: name)
        }
        let configuration = BrowserSchema.configuration(inMemory: inMemory, name: name, url: storeURL)
        do {
            return try BrowserSession(container: BrowserSchema.makeContainer(configuration))
        } catch {
            Logger.app.error("Unreadable store: \(error.logSummary, privacy: .public)")
            switch onFailure(error) {
            case .quit:
                return nil
            case .startOver:
                if let session = startOver(configuration) {
                    return session
                }
            case .continueWithoutSaving:
                break
            }
            // An empty in-memory store: nothing to read that could fail.
            // swiftlint:disable:next force_try
            return try! BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        }
    }

    /// The unreadable store put aside, a new one in its place; nil if that fails too.
    private static func startOver(_ configuration: ModelConfiguration) -> BrowserSession? {
        do {
            let aside = try BrowserSchema.moveAside(storeAt: configuration.url)
            Logger.app.notice("Unreadable store set aside: \(aside.lastPathComponent, privacy: .public)")
            return try BrowserSession(container: BrowserSchema.makeContainer(configuration))
        } catch {
            Logger.app.error("New store failed: \(error.logSummary, privacy: .public)")
            return nil
        }
    }

    /// The saved Spaces in order; at first launch, the default profile and Space. Throws if the store can't be read
    /// (an empty answer would create a second default profile and Space, audit R3).
    static func spaceRecords(in context: ModelContext) throws -> [SpaceRecord] {
        let records = try context.fetch(FetchDescriptor<SpaceRecord>(sortBy: [SortDescriptor(\.order)]))
        guard records.isEmpty else {
            return records
        }
        let profile = try context.fetch(FetchDescriptor<ProfileRecord>()).first ?? {
            let profile = ProfileRecord(name: defaultProfileName)
            context.insert(profile)
            return profile
        }()
        let space = SpaceRecord(name: defaultSpaceName, profile: profile)
        context.insert(space)
        try context.save()
        return [space]
    }

    /// Deletes the files of store `name` (`<name>.store`, `-shm`, `-wal`) in Application Support.
    private static func deleteStore(named name: String) {
        let manager = FileManager.default
        guard let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let files = try? manager.contentsOfDirectory(atPath: directory.path)
        else {
            return
        }
        for file in files where file.hasPrefix("\(name).store") {
            try? manager.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}
