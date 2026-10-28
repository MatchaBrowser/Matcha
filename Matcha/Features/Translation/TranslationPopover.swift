import SwiftUI

/// Popover of the translation button (task 9.3): the page's language and the target, which can be changed here (it
/// stays chosen for the next pages; a translated page is translated again), the state of the translation, and the
/// action that fits: “Translate”, “Show Original”, “Try Again”.
struct TranslationPopover: View {
    let page: BrowserTab
    let host: TranslationHost

    private var state: PageTranslation.State {
        page.translation.state
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if state == .translating {
                    ProgressView().controlSize(.small)
                }
                heading.font(.headline)
            }
            languages
            if isInTarget, let target = host.languages.target, !page.translation.isTranslated {
                Text(
                    "This page is already in \(TranslationLanguageName.inSentence(target)).",
                    comment: "Translation popover; %@ is a language as written in a sentence (“French”, “français”)",
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if case let .failed(failure) = state {
                Text(failure.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("translationFailure")
            }
            buttons
        }
        .padding(14)
        .frame(width: 300)
    }

    private var heading: Text {
        switch state {
        case .original: Text("Translate this page?", comment: "Title of the translation popover before the page is translated")
        case .translating: Text("Translating…", comment: "Title of the translation popover while the page is being translated")
        case .translated: Text("Page translated", comment: "Title of the translation popover once the page is translated")
        case .failed: Text("Translation failed", comment: "Title of the translation popover when the page couldn't be translated")
        }
    }

    /// “English → [French ▾]”.
    private var languages: some View {
        HStack(spacing: 6) {
            Text(page.translation.pageLanguage.map(TranslationLanguageName.of) ?? String(
                localized: "Page language",
                comment: "Translation popover, before the target language, when the page's language isn't known",
            ))
            .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Picker(selection: target) {
                ForEach(choices, id: \.minimalIdentifier) { language in
                    Text(TranslationLanguageName.of(language)).tag(language.minimalIdentifier)
                }
            } label: {
                Text("Translate to", comment: "Translation popover: accessibility label of the target language menu")
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("translationTargetPicker")
        }
        .font(.callout)
    }

    private var buttons: some View {
        HStack {
            Spacer()
            if page.translation.isTranslated {
                Button("Show Original") { PageTranslationActions.showOriginal(page) }
                    .accessibilityIdentifier("showOriginalButton")
            }
            if state == .original || state.isFailure {
                Button(state.isFailure ? String(localized: "Try Again") : String(
                    localized: "Translate",
                    comment: "Button of the translation popover: translates the page",
                )) {
                    PageTranslationActions.translate(page, host: host)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isInTarget)
                .accessibilityIdentifier("translateNowButton")
            }
        }
    }

    /// Languages of the menu: those the Mac can translate into, with the target even while they are unknown.
    private var choices: [Locale.Language] {
        let choices = host.languages.choices
        if let target = host.languages.target, !choices.contains(where: { PageLanguage.isSame($0, target) }) {
            return [target] + choices
        }
        return choices
    }

    /// The target, by the identifier of its line in the menu. Choosing one translates a translated page again.
    private var target: Binding<String> {
        Binding {
            let target = host.languages.target
            return choices.first { language in target.map { PageLanguage.isSame($0, language) } ?? false }?.minimalIdentifier ?? ""
        } set: { identifier in
            let language = Locale.Language(identifier: identifier)
            if page.translation.isTranslated {
                PageTranslationActions.translate(page, host: host, into: language)
            } else {
                host.languages.choose(language)
            }
        }
    }

    /// The page is already in the target language: nothing to translate until another one is chosen.
    private var isInTarget: Bool {
        guard let source = page.translation.pageLanguage, let target = host.languages.target else {
            return false
        }
        return PageLanguage.isSame(source, target)
    }
}

private extension PageTranslation.State {
    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
