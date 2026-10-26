import AppKit
import Foundation

/// Local files of the UI tests (review TS5), written by the tests, never read from macOS: a stand-in of the Postfix
/// documentation macOS ships, whose names, titles and links the tests were written against (home page with its logo,
/// “Basic configuration” and its “main.cf” links, all the parameters, the overview), a short tone, and a file WebKit
/// doesn't display. Written once per run in the runner's temporary folder; the app reads them there (its Debug build
/// reads the whole disk, review DI8).
enum UITestPages {
    /// Path of the file `name` of the folder.
    static func path(_ name: String) -> String {
        folder.appendingPathComponent(name).path
    }

    /// The home page of the documentation.
    static var index: String {
        path("index.html")
    }

    /// Several seconds of a quiet tone (WAV): WebKit opens it as a page that plays it by itself.
    static var tone: String {
        path("tone.wav")
    }

    /// A file WebKit doesn't display: opened, it is downloaded.
    static var undisplayable: String {
        path("firmware.dfu")
    }

    private static let folder: URL = {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MatchaUITestPages", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, html) in pages {
            try? Data(html.utf8).write(to: folder.appendingPathComponent(name))
        }
        try? logo().write(to: folder.appendingPathComponent("postfix-logo.jpg"))
        try? toneData(seconds: 20).write(to: folder.appendingPathComponent("tone.wav"))
        try? Data((0 ..< 65536).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 13) }).write(
            to: folder.appendingPathComponent("firmware.dfu"),
        )
        return folder
    }()

    private static let main = #"<a href="postconf.5.html">main.cf</a>"#

    private static let pages: [(String, String)] = [
        ("index.html", page("Postfix Documentation", """
        <h1><img src="postfix-logo.jpg" width="203" height="98" alt=""> Postfix Documentation </h1>
        <p>A local copy for the UI tests of Matcha: the postfix mail system, its configuration and its parameters.</p>
        <ul>
        <li> <a href="BASIC_CONFIGURATION_README.html"> Basic configuration </a>
        <li> <a href="OVERVIEW.html"> Architecture overview </a>
        <li> <a href="postconf.5.html"> All main.cf parameters </a>
        </ul>
        <p>Each postfix program reads its configuration when it starts.</p>
        """)),
        ("BASIC_CONFIGURATION_README.html", page("Postfix Basic Configuration", """
        <h1> Postfix Basic Configuration </h1>
        <p>The postfix configuration lives in the \(main) file; the most common parameters of \(main) are below.</p>
        <p>After a change of \(main), postfix reads its configuration again.</p>
        <p>Each parameter of \(main) has a default value; postfix only needs a few of them.</p>
        """)),
        ("postconf.5.html", page("Postfix Configuration Parameters", """
        <h1> Postfix Configuration Parameters </h1>
        \((1 ... 40).map { "<h2>parameter_\($0)</h2><p>Parameter \($0) of the postfix configuration.</p>" }.joined(separator: "\n"))
        """)),
        ("OVERVIEW.html", page("Postfix Architecture Overview", """
        <h1> Postfix Architecture Overview </h1>
        <p>How the postfix programs receive and deliver mail.</p>
        """)),
    ]

    private static func page(_ title: String, _ body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(title)</title></head>
        <body>
        \(body)
        </body></html>
        """
    }

    /// A 204 × 98 JPEG, like the documentation's logo.
    private static func logo() -> Data {
        let image = NSImage(size: NSSize(width: 204, height: 98), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [:])
        else {
            return Data()
        }
        return jpeg
    }

    /// `seconds` of a quiet 440 Hz tone, 16-bit mono PCM at 22 050 Hz.
    private static func toneData(seconds: Int) -> Data {
        let rate = 22050
        let samples = rate * seconds
        var data = Data()
        func append(_ value: some FixedWidthInteger) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + samples * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(samples * 2))
        for index in 0 ..< samples {
            append(Int16(sin(Double(index) * 2 * .pi * 440 / Double(rate)) * 3000))
        }
        return data
    }
}
