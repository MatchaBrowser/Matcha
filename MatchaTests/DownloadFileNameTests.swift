import Foundation
@testable import Matcha
import Testing

/// Nom du fichier d'un téléchargement : nom proposé rendu sûr, puis rendu unique (tâche 5.1).
struct DownloadFileNameTests {
    // MARK: Nom sûr

    @Test(arguments: [
        ("rapport.pdf", "rapport.pdf"),
        ("../../etc/passwd", "passwd"),
        ("/tmp/x/notes.txt", "notes.txt"),
        ("C:\\Users\\moi\\photo.jpg", "photo.jpg"),
        ("dossier/", "dossier"),
        (".bashrc", "bashrc"),
        ("...  .cache.tar.gz", "cache.tar.gz"),
        ("  espaces.txt  ", "espaces.txt"),
        ("ligne\nnouvelle\t.txt", "lignenouvelle.txt"),
        ("nul\u{0}\u{7F}\u{85}.bin", "nul.bin"),
        ("heure 12:30.txt", "heure 12-30.txt"),
        ("photo\u{202E}gpj.app", "photogpj.app"),
        ("\u{2066}isolé\u{2069}.txt", "isolé.txt"),
        ("café 👩‍💻.txt", "café 👩‍💻.txt"),
    ])
    func `suggested names are sanitized`(suggested: String, expected: String) {
        #expect(DownloadFileName.sanitized(suggested) == expected)
    }

    @Test(arguments: ["", "   ", "...", "/", "\u{202E}\u{0}", ". . ."])
    func `nothing usable gives an empty name`(suggested: String) {
        #expect(DownloadFileName.sanitized(suggested).isEmpty)
    }

    @Test func `long names are cut to 255 bytes keeping the extension`() {
        let name = DownloadFileName.sanitized(String(repeating: "é", count: 300) + ".tar.gz")
        #expect(name.utf8.count <= DownloadFileName.maximumLength)
        #expect(name.hasSuffix("é.tar.gz"))
    }

    @Test func `suggested name comes first, then the address, then the fallback`() throws {
        let url = try #require(URL(string: "https://example.com/files/archive.zip?token=1"))
        #expect(DownloadFileName.make(suggested: "rapport.pdf", url: url, mimeType: "application/pdf") == "rapport.pdf")
        #expect(DownloadFileName.make(suggested: "../", url: url, mimeType: nil) == "archive.zip")
        #expect(DownloadFileName.make(suggested: nil, url: URL(string: "https://example.com/"), mimeType: nil) == "download")
        #expect(DownloadFileName.make(suggested: "", url: nil, mimeType: nil) == DownloadFileName.fallback)
        #expect(DownloadFileName.make(suggested: nil, url: URL(fileURLWithPath: "/usr/share/a.bin"), mimeType: nil) == "a.bin")
    }

    /// Le « chemin » d'une adresse `data:` ou `blob:` n'est pas un nom de fichier.
    @Test func `data and blob addresses give no name`() {
        #expect(DownloadFileName
            .make(suggested: nil, url: URL(string: "data:text/plain,bonjour"), mimeType: "text/plain") == "download.txt")
        #expect(DownloadFileName.make(suggested: nil, url: URL(string: "blob:https://example.com/0f3e-77"), mimeType: nil) == "download")
    }

    @Test func `a name without extension gets the one of its type`() {
        #expect(DownloadFileName.make(suggested: "README", url: nil, mimeType: "text/plain") == "README.txt")
        #expect(DownloadFileName.make(suggested: "", url: nil, mimeType: "application/zip") == "download.zip")
        #expect(DownloadFileName.make(suggested: "archive.tar.gz", url: nil, mimeType: "text/plain") == "archive.tar.gz")
        #expect(DownloadFileName.make(suggested: "données", url: nil, mimeType: "application/octet-stream") == "données")
        #expect(DownloadFileName.make(suggested: "données", url: nil, mimeType: "pas un type") == "données")
    }

    // MARK: Extension

    @Test(arguments: [
        ("rapport.pdf", "rapport", ".pdf"),
        ("archive.tar.gz", "archive", ".tar.gz"),
        ("ARCHIVE.TAR.BZ2", "ARCHIVE", ".TAR.BZ2"),
        ("photo.de.vacances.jpg", "photo.de.vacances", ".jpg"),
        ("sans-extension", "sans-extension", ""),
        ("point.", "point.", ""),
        ("Notes v1.2 finale", "Notes v1.2 finale", ""),
        ("tar.gz", "tar", ".gz"),
        ("x.unextensiontroplongue12", "x.unextensiontroplongue12", ""),
    ])
    func `extensions are split`(name: String, base: String, pathExtension: String) {
        #expect(DownloadFileName.split(name) == (base, pathExtension))
    }

    // MARK: Nom unique

    @Test func `a free name is kept`() {
        #expect(DownloadFileName.unique("rapport.pdf") { _ in false } == "rapport.pdf")
    }

    @Test func `taken names are numbered from 2`() {
        let taken: Set = ["rapport.pdf", "rapport 2.pdf"]
        #expect(DownloadFileName.unique("rapport.pdf") { taken.contains($0) } == "rapport 3.pdf")
    }

    @Test func `compound extensions stay together`() {
        #expect(DownloadFileName.unique("archive.tar.gz") { $0 == "archive.tar.gz" } == "archive 2.tar.gz")
    }

    @Test func `names without extension are numbered at the end`() {
        #expect(DownloadFileName.unique("LISEZMOI") { $0 == "LISEZMOI" } == "LISEZMOI 2")
    }

    @Test func `numbered long names still fit in 255 bytes`() {
        let name = DownloadFileName.sanitized(String(repeating: "a", count: 300) + ".zip")
        let unique = DownloadFileName.unique(name) { $0 == name }
        #expect(unique.utf8.count <= DownloadFileName.maximumLength)
        #expect(unique.hasSuffix("a 2.zip"))
    }
}
