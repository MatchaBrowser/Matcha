import SwiftUI

/// Content of a sign-in window (task 5.8): the read-only address bar, the banner for the page's permission
/// requests (task 5.2), then the page (AppKit container, never recreated), or the message of a page that crashed
/// several times in a row (task 5.7). No navigation buttons and no address entry. The window title follows the
/// page's.
struct PopupWindowView: View {
    let controller: PopupWindowController

    private var tab: BrowserTab {
        controller.tab
    }

    var body: some View {
        VStack(spacing: 0) {
            PopupAddressBar(page: tab)
            PermissionBanner(prompts: tab.permissionPrompts)
            ZStack {
                MiniWebViewContainerView(container: controller.container)
                if tab.crash.isShowingProblem {
                    PageProblemView(page: tab)
                }
            }
        }
        .background(.background)
        // Title also read by VoiceOver, Mission Control and the Window menu; nothing before the page has an address.
        .onChange(of: windowTitle, initial: true) { _, title in controller.window.title = title }
    }

    private var windowTitle: String {
        tab.hasURL ? tab.displayTitle : ""
    }
}
