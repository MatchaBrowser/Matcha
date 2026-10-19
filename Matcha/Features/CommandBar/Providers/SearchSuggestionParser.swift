import Foundation

/// Reading of suggestion responses in the OpenSearch format: `["text", ["suggestion", …], …]`.
/// Google adds elements after the 2nd, ignored.
nonisolated enum SearchSuggestionParser {
    static let maximumCount = 8
    /// Kept length of a suggestion.
    static let maximumLength = 200

    /// Suggestions trimmed of surrounding whitespace, non-empty, cut at 200 characters, without duplicates (up to
    /// the folded text), in the engine's order, 8 at most. Throws `SearchSuggestionError.malformed` if the response
    /// does not have this shape or does not decode.
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

    /// `data` in UTF-8 when the response declares another character set (ISO-8859-1…); JSON only recognizes UTF-8,
    /// UTF-16 and UTF-32.
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
