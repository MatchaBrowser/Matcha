# Matcha

A native macOS browser built around a sidebar: colored Spaces, the page in a card with rounded corners, and a
command bar to go anywhere. Pages are displayed by WebKit, the engine of Safari; everything around them is written in
SwiftUI and AppKit.

> **Beta.** Matcha is young and still changing quickly. Expect rough edges, and please
> [report what breaks](https://github.com/MatchaBrowser/Matcha/issues/new).

## Features

- **Sidebar**: favorites, pinned tabs and folders, today's tabs; resizable, hidden with ⌃⌘S and revealed by hovering
  the left edge.
- **Spaces**, each with its own color theme; switch with ⌃1 to ⌃9 or a two-finger swipe on the sidebar.
- **Profiles**, with their own cookies and website data.
- **Command bar** (⌘T, ⌘L): open tabs, pinned tabs, history, search suggestions and actions in one field.
- **Split view**: up to four tabs side by side.
- **Peek**: Shift-click a link to preview it over the page.
- **Mini window**: a small floating window for a quick page (⌥⌘N), also from any app with a shortcut of your choice
  (Settings > Shortcuts).
- **Extensions**: Safari extensions of the apps you have installed, and extensions from a file (Chrome `.crx`,
  Firefox `.xpi`, `.zip` or a folder).
- **Import from Arc**: Spaces, pinned tabs, folders and favorites.
- Private windows, history, downloads, find in page, page zoom per site, site permissions (camera, microphone),
  printing and PDF export, sleeping of hidden tabs to save memory.
- In English, French, German, Spanish and Italian.

## Requirements

macOS 15.4 or later, on Apple silicon or Intel.

## Install

1. Download the disk image (`.dmg`) of the latest version from
   [Releases](https://github.com/MatchaBrowser/Matcha/releases).
2. Open it and drag Matcha to the Applications folder.
3. The current builds are not notarized by Apple yet, so macOS blocks the first launch. Open Matcha once and close
   the warning, then go to **System Settings > Privacy & Security**, scroll down to the message about Matcha and
   click **Open Anyway**.

## Not there yet

- **Sync** between Macs, end-to-end encrypted through a server you choose: the engine and the encryption are done, the
  server and its settings are not.
- **Passkeys and security keys** on websites: waiting for an entitlement from Apple.
- **Default browser**: Matcha can't be chosen as the default browser yet.
- **Automatic updates** and notarized builds.
- **Native messaging** of extensions (an extension talking to its Mac app, as password managers do) doesn't work in
  Matcha: the features of an extension that rely on it are missing.
- No built-in content blocker: use an extension such as uBlock Origin Lite.

## Build from source

You need Xcode 27.

```bash
git clone https://github.com/MatchaBrowser/Matcha.git
cd Matcha
open Matcha.xcodeproj
```

The project is signed with the maintainer's Apple team. In Xcode, pick your own team in the target's **Signing &
Capabilities** tab, or build from the command line signed to run locally:

```bash
xcodebuild -project Matcha.xcodeproj -scheme Matcha -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
open build/Build/Products/Debug/Matcha.app
```

### Checks

`scripts/check.sh` runs what the continuous integration runs: formatting (SwiftFormat), style (SwiftLint), a build
without warnings, the translations, the scripts' tests and the unit tests; the continuous integration also builds the
Release configuration (`MATCHA_CHECK_RELEASE=1`). It needs `brew install swiftformat swiftlint xcbeautify`.
Without a signing team, give it the same settings as above:

```bash
MATCHA_XCODEBUILD_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=" scripts/check.sh
```

The UI tests (`MatchaUITests`) drive the mouse and the keyboard: run them from Xcode, without touching the Mac
meanwhile.

### Layout

```
Matcha/
  App/          entry point, menus, shortcuts, settings
  Browser/      navigation: sessions, Spaces, tabs, WebKit configuration
  Models/       SwiftData models
  Services/     no user interface: favicons, downloads, history, extensions, import, sync
  Features/     the user interface, one folder per feature
  Resources/    string catalogs, credits
MatchaTests/    unit tests (Swift Testing)
MatchaUITests/  UI tests (XCTest)
scripts/        checks, packaging and publishing
```

The comments name documents such as `SYNC.md` (the sync format and the server's API), `DECISIONS.md` or
`TESTS_MANUELS.md` (manual checks): they are the maintainer's working documents, in French, kept on purpose outside
the repository.

## Contributing

Issues and pull requests are welcome. For a larger change, open an issue first so we can agree on it.

- Code, comments and log messages are in English. Texts of the interface are written in English in the code and
  translated in the same change into French, German, Spanish and Italian (`Matcha/Resources/*.xcstrings`).
- Public APIs only: no private selectors or undocumented keys.
- Pure logic (address parsing, ranking, import) goes in types without user interface, covered by tests.
- `scripts/check.sh` passes before a pull request.

## License

Matcha is licensed under the [Apache License 2.0](LICENSE); see also [NOTICE](NOTICE). The license doesn't grant the
use of the Matcha name or icon.

It includes [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, under the MIT
License.

Matcha is an independent project, not affiliated with Apple or with The Browser Company, the makers of Arc.
