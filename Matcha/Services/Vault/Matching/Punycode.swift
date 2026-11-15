import Foundation

/// Punycode (RFC 3492) and the per-label step of IDNA's ToASCII: what turns a host such as “bücher.de” into the
/// “xn--bcher-kva.de” the public suffix list compares (`VAULT.md` § 8.2). Of UTS #46, only the mappings that matter
/// for comparing hosts are applied: lowercasing, NFC, and the ideographic full stops read as dots. Pure type.
nonisolated enum Punycode {
    /// Prefix of an encoded label (the ACE prefix of RFC 3490).
    static let acePrefix = "xn--"

    private static let base = 36
    private static let tMin = 1
    private static let tMax = 26
    private static let skew = 38
    private static let damp = 700
    private static let initialBias = 72
    private static let initialN: UInt32 = 0x80
    /// Longest label of a domain name (RFC 1034), checked as ToASCII does (RFC 3490 § 4.1, step 8).
    static let maximumLabelLength = 63
    private static let delimiter = UInt8(ascii: "-")
    /// Full stops that IDNA reads as label separators: ideographic (U+3002), fullwidth (U+FF0E), halfwidth (U+FF61).
    private static let dotVariants: Set<Character> = ["\u{3002}", "\u{FF0E}", "\u{FF61}"]

    /// `host` with each non-ASCII label lowercased, in NFC, and encoded as “xn--” followed by its Punycode; ASCII
    /// labels are lowercased only. Empty labels and a final dot are kept for the caller to judge. Nil if a label
    /// can't be encoded, or is longer than `maximumLabelLength` once encoded.
    static func asciiHost(_ host: String) -> String? {
        if host.utf8.allSatisfy({ $0 < 0x80 }) {
            return host.lowercased()
        }
        let mapped = String(host.lowercased().precomposedStringWithCanonicalMapping.map { dotVariants.contains($0) ? "." : $0 })
        var labels: [String] = []
        for label in mapped.split(separator: ".", omittingEmptySubsequences: false) {
            guard let ascii = asciiLabel(label) else {
                return nil
            }
            labels.append(ascii)
        }
        return labels.joined(separator: ".")
    }

    /// `label` itself if it is ASCII, else “xn--” and its Punycode; nil if that is longer than `maximumLabelLength`.
    /// The encoding is at least as long as its text, so a longer text is refused before it is encoded (whose cost
    /// grows with the square of its length).
    private static func asciiLabel(_ label: Substring) -> String? {
        if label.utf8.allSatisfy({ $0 < 0x80 }) {
            return String(label)
        }
        guard label.unicodeScalars.count <= maximumLabelLength - acePrefix.count,
              let encoded = encode(String(label)).map({ acePrefix + $0 }),
              encoded.utf8.count <= maximumLabelLength
        else {
            return nil
        }
        return encoded
    }

    /// The Punycode of `text` (RFC 3492 § 6.3), without the ACE prefix: its basic code points in order, case kept, then
    /// a “-” if there were any, then the encoded insertions of the others. Nil on an overflow (a text far longer than a
    /// label).
    static func encode(_ text: String) -> String? {
        let input = text.unicodeScalars.map(\.value)
        var output = input.filter { $0 < initialN }.map { UInt8($0) }
        let basicCount = output.count
        if basicCount > 0 {
            output.append(delimiter)
        }
        var state = State(handled: basicCount)
        while state.handled < input.count {
            guard let next = input.filter({ $0 >= state.codePoint }).min(),
                  state.advance(to: next)
            else {
                return nil
            }
            for scalar in input {
                if scalar < state.codePoint {
                    guard state.incrementDelta() else {
                        return nil
                    }
                } else if scalar == state.codePoint {
                    state.emit(into: &output, isFirst: state.handled == basicCount)
                }
            }
            guard state.incrementDelta() else {
                return nil
            }
            state.codePoint += 1
        }
        return String(bytes: output, encoding: .ascii)
    }

    /// The variables of the encoding loop (RFC 3492 § 6.3: `n`, here `codePoint`, `delta`, `bias`, `h`).
    private struct State {
        var codePoint = Punycode.initialN
        var delta = 0
        var bias = Punycode.initialBias
        /// Code points already written (`h`).
        var handled: Int

        /// Moves `codePoint` to `next`, the smallest code point not yet written, counting the skipped states in
        /// `delta`; false on an overflow.
        mutating func advance(to next: UInt32) -> Bool {
            let (product, productOverflow) = Int(next - codePoint).multipliedReportingOverflow(by: handled + 1)
            let (sum, sumOverflow) = delta.addingReportingOverflow(product)
            guard !productOverflow, !sumOverflow else {
                return false
            }
            delta = sum
            codePoint = next
            return true
        }

        /// Adds one to `delta`; false on an overflow.
        mutating func incrementDelta() -> Bool {
            let (sum, overflow) = delta.addingReportingOverflow(1)
            delta = sum
            return !overflow
        }

        /// Writes `delta` as a generalized variable-length integer, then adapts the bias (RFC 3492 § 6.1).
        mutating func emit(into output: inout [UInt8], isFirst: Bool) {
            var remainder = delta
            var position = Punycode.base
            while true {
                let threshold = min(max(position - bias, Punycode.tMin), Punycode.tMax)
                if remainder < threshold {
                    break
                }
                let span = Punycode.base - threshold
                output.append(Punycode.digit(threshold + (remainder - threshold) % span))
                remainder = (remainder - threshold) / span
                position += Punycode.base
            }
            output.append(Punycode.digit(remainder))
            handled += 1
            bias = Punycode.adapt(delta: delta, count: handled, isFirst: isFirst)
            delta = 0
        }
    }

    /// The bias after a delta (RFC 3492 § 6.1).
    private static func adapt(delta: Int, count: Int, isFirst: Bool) -> Int {
        var delta = isFirst ? delta / damp : delta / 2
        delta += delta / count
        var position = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            position += base
        }
        return position + (base - tMin + 1) * delta / (delta + skew)
    }

    /// The basic code point of digit `value` (0…35): “a”…“z”, then “0”…“9”.
    private static func digit(_ value: Int) -> UInt8 {
        value < 26 ? UInt8(ascii: "a") + UInt8(value) : UInt8(ascii: "0") + UInt8(value - 26)
    }
}
