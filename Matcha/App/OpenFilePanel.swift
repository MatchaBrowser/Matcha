import AppKit
import UniformTypeIdentifiers

/// File > Open File… (⌘O, audit H1): the system's open panel, as a sheet on the active window, for the files a page
/// can show (web pages, web archives, PDF, images, text).
@MainActor
enum OpenFilePanel {
    static let contentTypes: [UTType] = [.html, .webArchive, .pdf, .image, .svg, .plainText, .xml, .json]

    /// `directory`: the folder shown first (a file to choose again, review ON14).
    static func choose(in directory: URL? = nil, multiple: Bool = true, completion: @escaping @MainActor ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = directory
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.allowedContentTypes = contentTypes
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, !panel.urls.isEmpty {
                completion(panel.urls)
            }
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil, !(window is NSPanel) {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
