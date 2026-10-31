import AppKit

/// Moments of the app's life the services follow, posted to `NotificationCenter.default` under this platform's names.
///
/// Not the same meaning everywhere: on the Mac, `willTerminate` comes before every normal quit. iOS sends it rarely: an
/// app in the background is killed without notice, so what must survive is saved before (to decide with the iOS app).
nonisolated enum AppLifecycle {
    /// The app is about to quit.
    static let willTerminate = NSApplication.willTerminateNotification
    /// The app has come to the front.
    static let didBecomeActive = NSApplication.didBecomeActiveNotification
}
