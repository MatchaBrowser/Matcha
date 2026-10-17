import Foundation

/// Lecture des réponses de suggestions au format OpenSearch : `["texte", ["suggestion", …], …]`.
/// Google ajoute des éléments après le 2e, ignorés.
nonisolated enum SearchSuggestionParser {
    static let maximumCount = 8
    /// Longueur gardée d'une suggestion.
    static let maximumLength = 200

    /// Suggestions sans espaces aux bords, non vides, coupées à 200 caractères, sans doublon (au texte
    /// replié près), dans l'ordre du moteur, 8 au plus. Lance `SearchSuggestionError.malformed` si la
    /// réponse n'a pas cette forme ou ne se décode pas.
    static func parse(_ data: Data, textEncodingName: String?) throws -> [String] {
        let json = try utf8Data(data, textEncodingName: textEncodingName)
        guard let response = try? JSONSerialization.jsonObject(with: json) as? [Any],
              response.count >= 2,
              let entries = response[1] as? [Any]
        else {
            throw SearchSuggestionError.malformed
        }
        var seen: Set<String> = []
        var suggestions: [String] = []
        for case let entry as String in entries where suggestions.count < maximumCount {
            let text = String(entry.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
            if !text.isEmpty, seen.insert(CommandText.fold(text)).inserted {
                suggestions.append(text)
            }
        }
        return suggestions
    }

    /// `data` en UTF-8 quand la réponse déclare un autre jeu de caractères (ISO-8859-1…) ; JSON
    /// reconnaît seul l'UTF-8, l'UTF-16 et l'UTF-32.
    private static func utf8Data(_ data: Data, textEncodingName: String?) throws -> Data {
        guard let textEncodingName else {
            return data
        }
        let declared = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
        guard declared != kCFStringEncodingInvalidId else {
            return data
        }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(declared))
        guard !unicodeEncodings.contains(encoding) else {
            return data
        }
        guard let text = String(data: data, encoding: encoding) else {
            throw SearchSuggestionError.malformed
        }
        return Data(text.utf8)
    }

    private static let unicodeEncodings: Set<String.Encoding> = [
        .utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian,
    ]
}
