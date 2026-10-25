import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Items dragged from the sidebar: dynamic type (no declaration in the Info.plist), known only to Matcha.
    /// Neither the page (`WKWebView`) nor another app accepts it. Never nil: macOS makes a dynamic type for any MIME
    /// type (a fallback such as `.data` would let pages accept it).
    static let matchaSidebarItem = UTType(
        mimeType: "application/x-matcha-sidebar-item",
        conformingTo: .data,
    )! // swiftlint:disable:this force_unwrapping
}
