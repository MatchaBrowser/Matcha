import Foundation
import UniformTypeIdentifiers

/// Nom du fichier d'un téléchargement, sans dépendance à l'interface : nom proposé rendu sûr, puis rendu unique
/// dans le dossier (« rapport.pdf », « rapport 2.pdf », « rapport 3.pdf »…).
nonisolated enum DownloadFileName {
    /// Nom de repli quand ni la page ni l'adresse n'en donnent un (comme Chrome), jamais traduit : c'est un nom
    /// de fichier.
    static let fallback = "download"
    /// Longueur maximale d'un nom de fichier (APFS), en octets UTF-8.
    static let maximumLength = 255
    /// Au-delà, ce qui suit le dernier point n'est pas une extension (« Notes v1.2 version longue »).
    static let maximumExtensionLength = 20
    /// Doubles extensions gardées ensemble : « archive 2.tar.gz », pas « archive.tar 2.gz ».
    static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz", "tar.lzma", "tar.lz4", "tar.z", "tar.bz"]
    /// Contrôles bidirectionnels : ils permettent de déguiser une extension (« photo », U+202E puis « gpj.app »
    /// s'affiche « photoppa.jpg »).
    private static let bidiControls = Set<UInt32>([0x061C, 0x200E, 0x200F]).union(0x202A ... 0x202E).union(0x2066 ... 0x2069)

    /// Nom proposé par la page ou WebKit, rendu sûr ; sinon le dernier composant de `url` (adresse à chemin : web ou
    /// fichier, pas `data:` ni `blob:`), sinon `fallback`. Un nom sans extension reçoit celle du type MIME s'il en a
    /// une (« README » envoyé en `text/plain` : « README.txt »).
    static func make(suggested: String?, url: URL?, mimeType: String?) -> String {
        let component = url.flatMap { $0.isFileURL || $0.host() != nil ? $0.lastPathComponent : nil }
        let name = [suggested, component].lazy.compactMap { $0.map(sanitized) }.first { !$0.isEmpty } ?? fallback
        guard split(name).extension.isEmpty, let mimeType,
              let preferred = UTType(mimeType: mimeType)?.preferredFilenameExtension
        else {
            return name
        }
        return fitted(name, suffix: "", extension: "." + preferred)
    }

    /// Dernier composant d'un chemin (`/` ou `\`), sans caractère de contrôle ni contrôle bidirectionnel, `:`
    /// remplacé par `-` (le Finder l'affiche comme `/`), sans point ni espace au début (pas de fichier caché), sans
    /// espace à la fin, et 255 octets au plus, extension comprise. Vide s'il ne reste rien.
    static func sanitized(_ suggested: String) -> String {
        let component = suggested.split { $0 == "/" || $0 == "\\" }.last.map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        // Caractères de contrôle C0 et C1 (retour à la ligne, tabulation, NUL…) et contrôles bidirectionnels.
        for scalar in component.unicodeScalars where scalar.properties.generalCategory != .control && !bidiControls.contains(scalar.value) {
            scalars.append(scalar == ":" ? "-" : scalar)
        }
        var name = Substring(String(scalars))
        while let first = name.first, first == "." || first.isWhitespace {
            name.removeFirst()
        }
        while let last = name.last, last.isWhitespace {
            name.removeLast()
        }
        let (base, pathExtension) = split(String(name))
        return fitted(base, suffix: "", extension: pathExtension)
    }

    /// Premier nom libre parmi `name`, « base 2.ext », « base 3.ext »… `isTaken` dit si un nom est déjà pris
    /// (fichier existant, ou téléchargement en cours qui ne l'a pas encore créé).
    static func unique(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else {
            return name
        }
        let (base, pathExtension) = split(name)
        for number in 2 ... 9999 {
            let candidate = fitted(base, suffix: " \(number)", extension: pathExtension)
            if !isTaken(candidate) {
                return candidate
            }
        }
        return fitted(base, suffix: " \(UUID().uuidString)", extension: pathExtension)
    }

    /// Nom et extension, point compris (« .pdf », « .tar.gz ») ; extension vide si le nom n'en a pas.
    static func split(_ name: String) -> (base: String, extension: String) {
        let lowercased = name.lowercased()
        if let compound = compoundExtensions.first(where: { lowercased.hasSuffix("." + $0) && lowercased.count > $0.count + 1 }) {
            let index = name.index(name.endIndex, offsetBy: -(compound.count + 1))
            return (String(name[..<index]), String(name[index...]))
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, "")
        }
        let pathExtension = name[name.index(after: dot)...]
        guard !pathExtension.isEmpty, pathExtension.count <= maximumExtensionLength, !pathExtension.contains(where: \.isWhitespace) else {
            return (name, "")
        }
        return (String(name[..<dot]), String(name[dot...]))
    }

    /// `base` + `suffix` + `pathExtension`, en raccourcissant `base` pour tenir en `maximumLength` octets.
    private static func fitted(_ base: String, suffix: String, extension pathExtension: String) -> String {
        var base = Substring(base)
        while !base.isEmpty, base.utf8.count + suffix.utf8.count + pathExtension.utf8.count > maximumLength {
            base.removeLast()
        }
        return base + suffix + pathExtension
    }
}
