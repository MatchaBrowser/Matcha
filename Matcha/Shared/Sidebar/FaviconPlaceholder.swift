import Foundation

/// Pill that replaces a site's icon: the domain's initial on a hue specific to the domain.
nonisolated enum FaviconPlaceholder {
    /// Initial of the domain, without “www.”, in uppercase; “?” without a domain.
    static func initial(for host: String?) -> String {
        let domain = host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        return domain.first.map { String($0).uppercased() } ?? "?"
    }

    /// Hue between 0 and 1, always the same for a given domain, from one launch to the next.
    static func hue(for host: String?) -> Double {
        // djb2: `hashValue` changes at each launch.
        let hash = (host ?? "").utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return Double(hash % 360) / 360
    }
}
