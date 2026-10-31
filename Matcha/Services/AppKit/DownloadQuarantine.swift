import CoreServices
import Foundation

/// Quarantine attribute (`com.apple.quarantine`) of downloaded files: Gatekeeper asks for confirmation the first
/// time an app, a script or a disk image is opened.
///
/// The sandbox sets it on its own on every file that WebKit writes for Matcha (agent “Matcha”, type “sandboxed”).
/// Matcha checks it at each finished download and sets it only if it is missing, through the public API
/// (`URLResourceValues.quarantineProperties`). It does not complete an existing attribute: a sandboxed app cannot
/// record the address in the macOS downloads log, the addition would only lose the type.
nonisolated enum DownloadQuarantine {
    /// Outcome of `ensure` (log and tests).
    enum Outcome: Equatable {
        /// The file already carried the attribute (set by the sandbox).
        case alreadyQuarantined
        /// The attribute was missing: Matcha set it.
        case added
        /// The attribute is missing and could not be set.
        case failed
    }

    /// Name of the app, the one the sandbox records in the attribute.
    static var agentName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Matcha"
    }

    /// Properties of a downloaded file: the app, the “web download” type, the address of the file and that of the
    /// page it comes from (http and https only: a `data:` address contains the file itself).
    static func properties(sourceURL: URL?, pageURL: URL?, agentName: String, bundleIdentifier: String?) -> [String: Any] {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: agentName,
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        properties[kLSQuarantineAgentBundleIdentifierKey as String] = bundleIdentifier
        properties[kLSQuarantineDataURLKey as String] = recordedURL(sourceURL)
        properties[kLSQuarantineOriginURLKey as String] = recordedURL(pageURL)
        return properties
    }

    /// Address recorded in the properties: http and https only, without user name or password.
    static func recordedURL(_ url: URL?) -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Quarantine properties of the file, nil if it has none (or if it is unreadable).
    static func currentProperties(of fileURL: URL) -> [String: Any]? {
        // Fresh URL: resource values are cached per object.
        try? URL(fileURLWithPath: fileURL.path).resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
    }

    /// Checks that the file carries the attribute, and sets it with `properties` if it is missing.
    static func ensure(on fileURL: URL, properties: @autoclosure () -> [String: Any]) -> Outcome {
        guard currentProperties(of: fileURL) == nil else {
            return .alreadyQuarantined
        }
        var target = URL(fileURLWithPath: fileURL.path)
        var values = URLResourceValues()
        values.quarantineProperties = properties()
        guard (try? target.setResourceValues(values)) != nil, currentProperties(of: fileURL) != nil else {
            return .failed
        }
        return .added
    }
}
