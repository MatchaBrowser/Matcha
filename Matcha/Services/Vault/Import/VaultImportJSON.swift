import Foundation

/// A JSON value of an imported file, walked without ever failing: a missing key, or a value of another type, reads as
/// empty (`""`, `[]`, nil), so that a malformed entry is skipped rather than the whole file. Parsed by
/// `JSONSerialization`, which bounds the nesting. Pure type.
nonisolated struct VaultImportJSON {
    private let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    /// The JSON of `data`; `VaultImportError.unreadable` if it isn't JSON.
    init(data: Data) throws {
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw VaultImportError.unreadable
        }
    }

    subscript(key: String) -> VaultImportJSON {
        VaultImportJSON(object?[key])
    }

    var isObject: Bool {
        object != nil
    }

    var isArray: Bool {
        value is [Any]
    }

    var isText: Bool {
        value is String
    }

    /// Absent, or `null`.
    var isNull: Bool {
        value == nil || value is NSNull
    }

    /// Keys of an object, sorted.
    var keys: [String] {
        object?.keys.sorted() ?? []
    }

    var array: [VaultImportJSON] {
        (value as? [Any])?.map(VaultImportJSON.init) ?? []
    }

    /// A text; a whole number in decimal (a month given as `4`); `""` for anything else.
    var string: String {
        if let text = value as? String {
            return text
        }
        if let integer {
            return String(integer)
        }
        return ""
    }

    var number: Double? {
        guard let number = value as? NSNumber, !Self.isBoolean(number) else {
            return nil
        }
        return number.doubleValue
    }

    /// A whole number below 2^53; nil otherwise.
    var integer: Int? {
        guard let number, number.rounded() == number, abs(number) < 9_007_199_254_740_992 else {
            return nil
        }
        return Int(number)
    }

    var bool: Bool? {
        guard let number = value as? NSNumber, Self.isBoolean(number) else {
            return nil
        }
        return number.boolValue
    }

    /// A date given in seconds (or milliseconds, `scale` 1000) since 1970; nil if absent or not a positive number.
    func date(scale: Double = 1) -> Date? {
        number.flatMap { Self.date($0, scale: scale) }
    }

    /// The date `number / scale` seconds after 1970; nil if not positive, or past the year 5000.
    static func date(_ number: Double, scale: Double) -> Date? {
        guard number > 0, number / scale < 95_617_584_000 else {
            return nil
        }
        return Date(timeIntervalSince1970: number / scale)
    }

    private var object: [String: Any]? {
        value as? [String: Any]
    }

    /// `true` and `false` arrive as `NSNumber` too: told apart by their Core Foundation type.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
