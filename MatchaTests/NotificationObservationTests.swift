import Foundation
@testable import Matcha
import Testing
import WebKit

/// Observers removed with their object, whatever the thread that releases it.
struct NotificationObservationTests {
    @MainActor
    private final class Counter {
        var value = 0
    }

    @MainActor
    @Test func `the observer goes away with its object`() {
        let name = Notification.Name("NotificationObservationTests")
        let center = NotificationCenter()
        let counter = Counter()
        var observation: NotificationObservation? = NotificationObservation(of: name, center: center) { _ in
            MainActor.assumeIsolated { counter.value += 1 }
        }
        center.post(name: name, object: nil)
        #expect(counter.value == 1)
        #expect(observation != nil)

        observation = nil
        center.post(name: name, object: nil)
        #expect(counter.value == 1)
    }

    /// Like Swift Testing with a suite's properties: the managers are released outside the main actor. Their
    /// `isolated deinit`, built by Xcode 26, crashed there (CI, 2026-10-21).
    @Test func `managers released outside the main thread go away cleanly`() async {
        let downloads = await DownloadManager(directory: { nil })
        let extensions = await ExtensionManager(configuration: .nonPersistent(), store: ExtensionStateStore(defaults: nil), directory: nil)
        #expect(await downloads.items.isEmpty)
        #expect(await extensions.contexts.isEmpty)
    }
}
