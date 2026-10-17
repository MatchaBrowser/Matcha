import Foundation

/// Transforme le texte tapé dans le champ d'adresse en URL :
/// adresse complète telle quelle, hôte auquel on ajoute un schéma, ou recherche.
nonisolated struct AddressResolver: Sendable {
    var searchEngine = SearchEngine.defaultEngine

    /// Schémas acceptés tels quels.
    static let directSchemes: Set<String> = ["http", "https", "file", "about"]

    /// URL à ouvrir pour `input`, ou nil si le texte est vide.
    func resolve(_ input: String) -> URL? {
        interpret(input)?.url
    }

    /// Lecture de `input` : adresse (schéma accepté tel quel, ou hôte auquel on ajoute un schéma)
    /// ou recherche ; nil si le texte est vide.
    func interpret(_ input: String) -> AddressInterpretation? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), Self.directSchemes.contains(scheme) {
            return .address(url)
        }
        if let url = hostURL(for: text) {
            return .address(url)
        }
        return searchEngine.searchURL(for: text).map(AddressInterpretation.search)
    }

    /// URL complète si `text` ressemble à « hôte[:port][/chemin] », sans espace.
    /// Les hôtes locaux (localhost, adresses IP, `.local`) reçoivent `http://`, les autres `https://`.
    private func hostURL(for text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else {
            return nil
        }
        let authorityEnd = text.firstIndex { "/?#".contains($0) } ?? text.endIndex
        guard let kind = HostKind(authority: text[..<authorityEnd]) else {
            return nil
        }
        let scheme = kind == .local ? "http" : "https"
        return URL(string: "\(scheme)://\(text)")
    }
}

/// Ce que désigne un texte tapé : une adresse à ouvrir ou une recherche à lancer.
nonisolated enum AddressInterpretation: Equatable, Sendable {
    case address(URL)
    /// Recherche du texte sur le moteur choisi ; l'URL est celle de la page de résultats.
    case search(URL)

    var url: URL {
        switch self {
        case let .address(url), let .search(url): url
        }
    }
}

/// Nature de la partie « hôte[:port] » d'une adresse tapée sans schéma.
private nonisolated enum HostKind {
    /// Nom de domaine public, servi en HTTPS.
    case domain
    /// localhost, adresse IP ou nom `.local` : serveurs de développement, box, imprimantes.
    case local

    /// Nil si `authority` ne ressemble pas à un hôte.
    init?(authority: Substring) {
        // Un « @ » signale plutôt une adresse e-mail, qu'on cherche.
        guard !authority.isEmpty, !authority.contains("@") else {
            return nil
        }
        if authority.hasPrefix("[") {
            guard Self.isBracketedIPv6(authority) else {
                return nil
            }
            self = .local
            return
        }
        var host = authority
        if let colon = authority.lastIndex(of: ":") {
            guard Self.isPort(authority[authority.index(after: colon)...]) else {
                return nil
            }
            host = authority[..<colon]
        }
        let name = host.lowercased()
        if name == "localhost" || Self.isIPv4(name) {
            self = .local
        } else if Self.isDomainName(name) {
            self = name.hasSuffix(".local") || name.hasSuffix(".localhost") ? .local : .domain
        } else {
            return nil
        }
    }

    /// « [::1] » ou « [::1]:8080 ».
    private static func isBracketedIPv6(_ authority: Substring) -> Bool {
        guard let close = authority.firstIndex(of: "]") else {
            return false
        }
        let address = authority[authority.index(after: authority.startIndex) ..< close]
        let rest = authority[authority.index(after: close)...]
        let validRest = rest.isEmpty || (rest.first == ":" && isPort(rest.dropFirst()))
        let validAddress = address.contains(":") && address.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        return validRest && validAddress
    }

    private static func isPort(_ text: Substring) -> Bool {
        guard (1 ... 5).contains(text.count), text.allSatisfy(isASCIIDigit), let port = Int(text) else {
            return false
        }
        return (1 ... 65535).contains(port)
    }

    private static func isIPv4(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            (1 ... 3).contains(part.count) && part.allSatisfy(isASCIIDigit) && (Int(part) ?? 256) <= 255
        }
    }

    /// Au moins deux étiquettes séparées par des points, la dernière contenant une lettre :
    /// « apple.com » oui, « 6.4 » non. Un point final est toléré.
    private static func isDomainName(_ text: String) -> Bool {
        var labels = text.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count > 2, labels.last?.isEmpty == true {
            labels.removeLast()
        }
        guard labels.count >= 2, labels.allSatisfy(isLabel), let topLevel = labels.last else {
            return false
        }
        return topLevel.contains(where: \.isLetter)
    }

    private static func isLabel(_ label: Substring) -> Bool {
        guard let first = label.first, let last = label.last, first != "-", last != "-" else {
            return false
        }
        return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
