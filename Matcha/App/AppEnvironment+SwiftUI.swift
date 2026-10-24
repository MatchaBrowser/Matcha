import SwiftUI

extension View {
    /// What the windows' views take from the composition root (audit C2): observed objects, and the others through
    /// their environment values.
    func appServices(_ environment: AppEnvironment) -> some View {
        self.environment(environment.downloads)
            .environment(environment.extensions)
            .environment(environment.settingsSelection)
            .environment(environment.sync)
            .environment(\.extensionWindows, environment.extensionWindows)
            .environment(\.pageFind, environment.pageFind)
    }
}
