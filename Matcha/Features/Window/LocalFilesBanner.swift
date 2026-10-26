import SwiftUI

/// Banner of a local page that reads only itself (received from another app, review WB11) but refers to files next to
/// it: they don't show. “Open…” opens the file panel on its folder: the page chosen there reads its folder, as with
/// ⌘O. “Close” hides the banner for this document.
struct LocalFilesBanner: View {
    let page: BrowserTab

    var body: some View {
        VStack(spacing: 0) {
            if page.localFiles.hasUnreadableNeighbors, let url = page.url {
                LocalFilesBannerContent(page: page, url: url)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
        }
        .clipped()
        .motionAnimation(.easeOut(duration: 0.2), value: page.localFiles.hasUnreadableNeighbors)
    }
}

private struct LocalFilesBannerContent: View {
    let page: BrowserTab
    let url: URL

    var body: some View {
        PromptBannerLayout(
            label: String(
                localized: "Files Not Shown",
                comment: "Accessibility label of the banner of a local page that can't show the files next to it",
            ),
            identifier: "localFilesBanner",
        ) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } message: {
            Text(
                "This page opened from another app can't show the files next to it, such as its images. To show them, open it with ⌘O.",
                comment: "Banner of a local page received from another app (Finder…): the images of its folder are not shown",
            )
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("localFilesMessage")
        } buttons: {
            Button {
                page.localFiles.dismiss()
            } label: {
                Text("Close", comment: "Banner of a local page that can't show its images: hide the banner")
            }
            .accessibilityIdentifier("localFilesCloseButton")
            Button {
                OpenFilePanel.choose(in: url.deletingLastPathComponent(), multiple: false) { urls in
                    urls.first.map(page.openChosenFile)
                }
            } label: {
                Text("Open…", comment: "Banner of a local page that can't show its images: opens the file panel, as File > Open File…")
            }
            .accessibilityIdentifier("localFilesOpenButton")
        }
    }
}
