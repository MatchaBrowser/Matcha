import Foundation

/// Deletion of a folder that may be large (an extension and its resources), off the main thread (review EX19). Pure
/// type.
nonisolated enum FileRemoval {
    /// Deletes `url`; false if it couldn't be (nothing to delete included).
    @concurrent
    @discardableResult
    static func remove(_ url: URL) async -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
