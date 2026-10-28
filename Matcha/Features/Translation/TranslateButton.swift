import SwiftUI

/// Translation button next to the address pill (task 9.3): on every web page and local file, even one already in the
/// target language (the popover chooses another one); tinted when the page is translated. A click opens its popover:
/// languages, state, “Translate” or “Show Original”. Needs the window's sessions (`TranslationHost` in the environment).
struct TranslateButton: View {
    /// Described page: displayed tab, page of the peek or of the mini window.
    let page: BrowserTab?

    @Environment(TranslationHost.self) private var host: TranslationHost?
    @State private var isPresented = false

    static func isShown(for page: BrowserTab?) -> Bool {
        PageTranslationActions.canTranslate(page)
    }

    var body: some View {
        if let page, let host, Self.isShown(for: page) {
            let isTranslated = page.translation.isTranslated
            Button { isPresented.toggle() } label: {
                Label { title(isTranslated: isTranslated) } icon: { Image(systemName: "translate") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .foregroundStyle(isTranslated ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isPresented ? 0.12 : 0)))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                TranslationPopover(page: page, host: host)
            }
            .help(title(isTranslated: isTranslated))
            .accessibilityAddTraits(isTranslated ? .isSelected : [])
            .accessibilityIdentifier("translateButton")
            .transition(.opacity)
        }
    }

    private func title(isTranslated: Bool) -> Text {
        isTranslated
            ? Text("Translated Page", comment: "Button next to the address of a translated page; opens its translation popover")
            : Text("Translate Page")
    }
}
